import NimQml, os, json, sequtils, strutils, uuids, times
import json_serialization, chronicles

import ../../../app/global/global_singleton
import ./dto/accounts as dto_accounts
import ./dto/generated_accounts as dto_generated_accounts
from ../keycard/service import KeycardEvent, KeyDetails 
import ../../../backend/general as status_general
import ../../../backend/core as status_core

import ../../../app/core/eventemitter
import ../../../app/core/signals/types
import ../../../app/core/tasks/[qt, threadpool]
import ../../../app/core/fleets/fleet_configuration
import ../../common/[account_constants, network_constants, utils, string_utils]
import ../../../constants as main_constants

import ../settings/dto/settings as settings

export dto_accounts
export dto_generated_accounts


logScope:
  topics = "accounts-service"

const PATHS = @[PATH_WALLET_ROOT, PATH_EIP_1581, PATH_WHISPER, PATH_DEFAULT_WALLET, PATH_ENCRYPTION]
const ACCOUNT_ALREADY_EXISTS_ERROR =  "account already exists"
const output_csv {.booldefine.} = false
const KDF_ITERATIONS* {.intdefine.} = 256_000

# allow runtime override via environment variable. core contributors can set a
# specific peer to set for testing messaging and mailserver functionality with squish.
let TEST_PEER_ENR = getEnv("TEST_PEER_ENR").string

const SIGNAL_CONVERTING_PROFILE_KEYPAIR* = "convertingProfileKeypair"

type ResultArgs* = ref object of Args
  success*: bool

include utils
include async_tasks

QtObject:
  type Service* = ref object of QObject
    events: EventEmitter
    threadpool: ThreadPool
    fleetConfiguration: FleetConfiguration
    generatedAccounts: seq[GeneratedAccountDto]
    accounts: seq[AccountDto]
    loggedInAccount: AccountDto
    importedAccount: GeneratedAccountDto
    isFirstTimeAccountLogin: bool
    keyStoreDir: string
    defaultWalletEmoji: string

  proc delete*(self: Service) =
    self.QObject.delete

  proc newService*(events: EventEmitter, threadpool: ThreadPool, fleetConfiguration: FleetConfiguration): Service =
    new(result, delete)
    result.QObject.setup
    result.events = events
    result.threadpool = threadpool
    result.fleetConfiguration = fleetConfiguration
    result.isFirstTimeAccountLogin = false
    result.keyStoreDir = main_constants.ROOTKEYSTOREDIR
    result.defaultWalletEmoji = ""

  proc getLoggedInAccount*(self: Service): AccountDto =
    return self.loggedInAccount

  proc getImportedAccount*(self: Service): GeneratedAccountDto =
    return self.importedAccount

  proc isFirstTimeAccountLogin*(self: Service): bool =
    return self.isFirstTimeAccountLogin

  proc setKeyStoreDir(self: Service, key: string) = 
    self.keyStoreDir = joinPath(main_constants.ROOTKEYSTOREDIR, key) & main_constants.sep
    discard status_general.initKeystore(self.keyStoreDir)

  proc getKeyStoreDir*(self: Service): string = 
    return self.keyStoreDir

  proc setDefaultWalletEmoji*(self: Service, emoji: string) =
    self.defaultWalletEmoji = emoji

  proc init*(self: Service) =
    try:
      let response = status_account.generateAddresses(PATHS)

      self.generatedAccounts = map(response.result.getElems(),
      proc(x: JsonNode): GeneratedAccountDto = toGeneratedAccountDto(x))

      for account in self.generatedAccounts.mitems:
        account.alias = generateAliasFromPk(account.derivedAccounts.whisper.publicKey)

    except Exception as e:
      error "error: ", procName="init", errName = e.name, errDesription = e.msg

  proc clear*(self: Service) =
    self.generatedAccounts = @[]
    self.loggedInAccount = AccountDto()
    self.importedAccount = GeneratedAccountDto()
    self.isFirstTimeAccountLogin = false

  proc validateMnemonic*(self: Service, mnemonic: string): string =
    try:
      let response = status_general.validateMnemonic(mnemonic)

      var error = "response doesn't contain \"error\""
      if(response.result.contains("error")):
        error = response.result["error"].getStr

      # An empty error means that mnemonic is valid.
      return error

    except Exception as e:
      error "error: ", procName="validateMnemonic", errName = e.name, errDesription = e.msg

  proc generatedAccounts*(self: Service): seq[GeneratedAccountDto] =
    if(self.generatedAccounts.len == 0):
      error "There was some issue initiating account service"
      return

    result = self.generatedAccounts

  proc openedAccounts*(self: Service): seq[AccountDto] =
    try:
      let response = status_account.openedAccounts(main_constants.STATUSGODIR)

      self.accounts = map(response.result.getElems(), proc(x: JsonNode): AccountDto = toAccountDto(x))

      return self.accounts

    except Exception as e:
      error "error: ", procName="openedAccounts", errName = e.name, errDesription = e.msg

  proc storeDerivedAccounts(self: Service, accountId, hashedPassword: string,
    paths: seq[string]): DerivedAccounts =
    let response = status_account.storeDerivedAccounts(accountId, hashedPassword, paths)

    if response.result.contains("error"):
      raise newException(Exception, response.result["error"].getStr)

    result = toDerivedAccounts(response.result)

  proc storeAccount(self: Service, accountId, hashedPassword: string): GeneratedAccountDto =
    let response = status_account.storeAccounts(accountId, hashedPassword)

    if response.result.contains("error"):
      raise newException(Exception, response.result["error"].getStr)

    result = toGeneratedAccountDto(response.result)

  proc saveAccountAndLogin(self: Service, hashedPassword: string, account,
    subaccounts, settings, config: JsonNode): AccountDto =
    try:
      let response = status_account.saveAccountAndLogin(hashedPassword, account, subaccounts, settings, config)

      var error = "response doesn't contain \"error\""
      if(response.result.contains("error")):
        error = response.result["error"].getStr
        if error == "":
          debug "Account saved succesfully"
          self.isFirstTimeAccountLogin = true
          result = toAccountDto(account)
          return

      let err = "Error saving account and logging in: " & error
      error "error: ", procName="saveAccountAndLogin", errDesription = err

    except Exception as e:
      error "error: ", procName="saveAccountAndLogin", errName = e.name, errDesription = e.msg

  proc saveKeycardAccountAndLogin(self: Service, chatKey, password: string, account, subaccounts, settings, 
    config: JsonNode): AccountDto =
    try:
      let response = status_account.saveAccountAndLoginWithKeycard(chatKey, password, account, subaccounts, settings, config)

      var error = "response doesn't contain \"error\""
      if(response.result.contains("error")):
        error = response.result["error"].getStr
        if error == "":
          debug "Account saved succesfully"
          result = toAccountDto(account)
          return

      let err = "Error saving account and logging in via keycard : " & error
      error "error: ", procName="saveKeycardAccountAndLogin", errDesription = err

    except Exception as e:
      error "error: ", procName="saveKeycardAccountAndLogin", errName = e.name, errDesription = e.msg

  proc prepareAccountJsonObject(self: Service, account: GeneratedAccountDto, displayName: string): JsonNode =
    result = %* {
      "name": if displayName == "": account.alias else: displayName,
      "address": account.address,
      "key-uid": account.keyUid,
      "keycard-pairing": nil,
      "kdfIterations": KDF_ITERATIONS,
    }

  proc getAccountDataForAccountId(self: Service, accountId: string, displayName: string): JsonNode =
    for acc in self.generatedAccounts:
      if(acc.id == accountId):
        return self.prepareAccountJsonObject(acc, displayName)

    if(self.importedAccount.isValid()):
      if(self.importedAccount.id == accountId):
        return self.prepareAccountJsonObject(self.importedAccount, displayName)

  proc prepareSubaccountJsonObject(self: Service, account: GeneratedAccountDto, displayName: string):
    JsonNode =
    result = %* [
      {
        "public-key": account.derivedAccounts.defaultWallet.publicKey,
        "address": account.derivedAccounts.defaultWallet.address,
        "color": "#4360df",
        "wallet": true,
        "path": PATH_DEFAULT_WALLET,
        "name": "Status account",
        "derived-from": account.address,
        "emoji": self.defaultWalletEmoji
      },
      {
        "public-key": account.derivedAccounts.whisper.publicKey,
        "address": account.derivedAccounts.whisper.address,
        "name": if displayName == "": account.alias else: displayName,
        "path": PATH_WHISPER,
        "chat": true,
        "derived-from": ""
      }
    ]

  proc getSubaccountDataForAccountId(self: Service, accountId: string, displayName: string): JsonNode =
    for acc in self.generatedAccounts:
      if(acc.id == accountId):
        return self.prepareSubaccountJsonObject(acc, displayName)

    if(self.importedAccount.isValid()):
      if(self.importedAccount.id == accountId):
        return self.prepareSubaccountJsonObject(self.importedAccount, displayName)

  proc prepareAccountSettingsJsonObject(self: Service, account: GeneratedAccountDto,
    installationId: string, displayName: string): JsonNode =
    result = %* {
      "key-uid": account.keyUid,
      "mnemonic": account.mnemonic,
      "public-key": account.derivedAccounts.whisper.publicKey,
      "name": account.alias,
      "display-name": displayName,
      "address": account.address,
      "eip1581-address": account.derivedAccounts.eip1581.address,
      "dapps-address": account.derivedAccounts.defaultWallet.address,
      "wallet-root-address": account.derivedAccounts.walletRoot.address,
      "preview-privacy?": true,
      "signing-phrase": generateSigningPhrase(3),
      "log-level": $LogLevel.INFO,
      "latest-derived-path": 0,
      "currency": "usd",
      "networks/networks": @[],
      "networks/current-network": "",
      "wallet/visible-tokens": {},
      "waku-enabled": true,
      "appearance": 0,
      "installation-id": installationId,
      "current-user-status": %* {
          "publicKey": account.derivedAccounts.whisper.publicKey,
          "statusType": 1,
          "clock": 0,
          "text": ""
        },
      "profile-pictures-show-to": settings.PROFILE_PICTURES_SHOW_TO_EVERYONE,
      "profile-pictures-visibility": settings.PROFILE_PICTURES_VISIBILITY_EVERYONE
    }

  proc getAccountSettings(self: Service, accountId: string,
    installationId: string,
    displayName: string): JsonNode =
    for acc in self.generatedAccounts:
      if(acc.id == accountId):
        return self.prepareAccountSettingsJsonObject(acc, installationId, displayName)

    if(self.importedAccount.isValid()):
      if(self.importedAccount.id == accountId):
        return self.prepareAccountSettingsJsonObject(self.importedAccount, installationId, displayName)

  proc getDefaultNodeConfig*(self: Service, installationId: string): JsonNode =
    let fleet = Fleet.StatusProd
    let dnsDiscoveryURL = @["enrtree://AOGECG2SPND25EEFMAJ5WF3KSGJNSGV356DSTL2YVLLZWIV6SAYBM@prod.nodes.status.im"]

    result = NODE_CONFIG.copy()
    result["ClusterConfig"]["Fleet"] = newJString($fleet)
    result["ClusterConfig"]["BootNodes"] = %* self.fleetConfiguration.getNodes(fleet, FleetNodes.Bootnodes)
    result["ClusterConfig"]["TrustedMailServers"] = %* self.fleetConfiguration.getNodes(fleet, FleetNodes.Mailservers)
    result["ClusterConfig"]["StaticNodes"] = %* self.fleetConfiguration.getNodes(fleet, FleetNodes.Whisper)
    result["ClusterConfig"]["RendezvousNodes"] = %* self.fleetConfiguration.getNodes(fleet, FleetNodes.Rendezvous)
    result["NetworkId"] = NETWORKS[0]{"chainId"}
    result["DataDir"] = "ethereum".newJString()
    result["UpstreamConfig"]["Enabled"] = true.newJBool()
    result["UpstreamConfig"]["URL"] = NETWORKS[0]{"rpcUrl"}
    result["ShhextConfig"]["InstallationID"] = newJString(installationId)
    result["NoDiscovery"] = true.newJBool()
    result["Rendezvous"] = false.newJBool()

    # TODO: fleet.status.im should have different sections depending on the node type
    #       or maybe it's not necessary because a node has the identify protocol
    result["ClusterConfig"]["WakuNodes"] = %* dnsDiscoveryURL
    result["ClusterConfig"]["DiscV5BootstrapNodes"] = %* dnsDiscoveryURL

    result["WakuV2Config"]["EnableDiscV5"] = true.newJBool()
    result["WakuV2Config"]["DiscoveryLimit"] = 20.newJInt()
    result["WakuV2Config"]["Rendezvous"] = true.newJBool()
    result["WakuV2Config"]["Enabled"] = true.newJBool()

    result["WakuConfig"]["Enabled"] = false.newJBool()

    if existsEnv("WAKUV2_PORT"):
      let wV2Port = parseInt($getEnv("WAKUV2_PORT"))
      # Waku V2 config
      result["WakuV2Config"]["Port"] = wV2Port.newJInt()
      result["WakuV2Config"]["UDPPort"] = wV2Port.newJInt()

    if TEST_PEER_ENR != "":
      let testPeerENRArr = %* @[TEST_PEER_ENR]
      result["ClusterConfig"]["WakuNodes"] = %* testPeerENRArr
      result["ClusterConfig"]["BootNodes"] = %* testPeerENRArr
      result["ClusterConfig"]["TrustedMailServers"] = %* testPeerENRArr
      result["ClusterConfig"]["StaticNodes"] = %* testPeerENRArr
      result["ClusterConfig"]["RendezvousNodes"] = %* (@[])
      result["ClusterConfig"]["DiscV5BootstrapNodes"] = %* (@[])
      result["Rendezvous"] = newJBool(false)

    result["KeyStoreDir"] = newJString(self.keyStoreDir.replace(main_constants.STATUSGODIR, ""))

  proc setLocalAccountSettingsFile(self: Service) =
    if(defined(macosx) and self.getLoggedInAccount.isValid()):
      singletonInstance.localAccountSettings.setFileName(self.getLoggedInAccount.name)

  proc addKeycardDetails(self: Service, settingsJson: var JsonNode, accountData: var JsonNode) =
    let keycardPairingJsonString = readFile(main_constants.KEYCARDPAIRINGDATAFILE)
    let keycardPairingJsonObj = keycardPairingJsonString.parseJSON
    let now = now().toTime().toUnix()
    for instanceUid, kcDataObj in keycardPairingJsonObj:
      if not settingsJson.isNil:
        settingsJson["keycard-instance-uid"] = %* instanceUid
        settingsJson["keycard-paired-on"] = %* now
        settingsJson["keycard-pairing"] = kcDataObj{"key"}
      if not accountData.isNil:
        accountData["keycard-pairing"] = kcDataObj{"key"}

  proc setupAccount*(self: Service, accountId, password, displayName: string): string =
    try:
      let installationId = $genUUID()
      var accountDataJson = self.getAccountDataForAccountId(accountId, displayName)
      self.setKeyStoreDir(accountDataJson{"key-uid"}.getStr) # must be called before `getDefaultNodeConfig`
      let subaccountDataJson = self.getSubaccountDataForAccountId(accountId, displayName)
      var settingsJson = self.getAccountSettings(accountId, installationId, displayName)
      let nodeConfigJson = self.getDefaultNodeConfig(installationId)

      if(accountDataJson.isNil or subaccountDataJson.isNil or settingsJson.isNil or
        nodeConfigJson.isNil):
        let description = "at least one json object is not prepared well"
        error "error: ", procName="setupAccount", errDesription = description
        return description

      let hashedPassword = hashString(password)
      discard self.storeAccount(accountId, hashedPassword)
      discard self.storeDerivedAccounts(accountId, hashedPassword, PATHS)
      self.loggedInAccount = self.saveAccountAndLogin(hashedPassword, 
        accountDataJson,
        subaccountDataJson, 
        settingsJson, 
        nodeConfigJson)
      
      self.setLocalAccountSettingsFile()

      if self.getLoggedInAccount.isValid():
        return ""
      else:
        return "logged in account is not valid"
    except Exception as e:
      error "error: ", procName="setupAccount", errName = e.name, errDesription = e.msg
      return e.msg

  proc setupAccountKeycard*(self: Service, keycardData: KeycardEvent, useImportedAcc: bool) = 
    try:
      var keyUid = keycardData.keyUid
      var address = keycardData.masterKey.address
      var whisperPrivateKey = keycardData.whisperKey.privateKey
      var whisperPublicKey = keycardData.whisperKey.publicKey
      var whisperAddress = keycardData.whisperKey.address
      var walletPublicKey = keycardData.walletKey.publicKey
      var walletAddress = keycardData.walletKey.address
      var walletRootAddress = keycardData.walletRootKey.address
      var eip1581Address = keycardData.eip1581Key.address
      var encryptionPublicKey = keycardData.encryptionKey.publicKey
      if useImportedAcc:
        keyUid = self.importedAccount.keyUid
        address = self.importedAccount.address
        whisperPublicKey = self.importedAccount.derivedAccounts.whisper.publicKey
        whisperAddress = self.importedAccount.derivedAccounts.whisper.address
        walletPublicKey = self.importedAccount.derivedAccounts.defaultWallet.publicKey
        walletAddress = self.importedAccount.derivedAccounts.defaultWallet.address
        walletRootAddress = self.importedAccount.derivedAccounts.walletRoot.address
        eip1581Address = self.importedAccount.derivedAccounts.eip1581.address
        encryptionPublicKey = self.importedAccount.derivedAccounts.encryption.publicKey

        whisperPrivateKey = self.importedAccount.derivedAccounts.whisper.privateKey
        if whisperPrivateKey.startsWith("0x"):
          whisperPrivateKey = whisperPrivateKey[2 .. ^1]

      let installationId = $genUUID()
      let alias = generateAliasFromPk(whisperPublicKey)
      
      let openedAccounts = self.openedAccounts()
      var displayName: string
      for acc in openedAccounts:
        if acc.keyUid == keyUid:
          displayName = acc.name
          break
      if displayName.len == 0:
        displayName = self.getLoggedInAccount().name

      var accountDataJson = %* {
        "name": alias,
        "display-name": displayName,
        "address": address,
        "key-uid": keyUid,
        "kdfIterations": KDF_ITERATIONS,
      }

      self.setKeyStoreDir(keyUid)
      let nodeConfigJson = self.getDefaultNodeConfig(installationId)
      let subaccountDataJson = %* [
        {
          "public-key": walletPublicKey,
          "address": walletAddress,
          "color": "#4360df",
          "wallet": true,
          "path": PATH_DEFAULT_WALLET,
          "name": "Status account",
          "derived-from": address,
          "emoji": self.defaultWalletEmoji,
        },
        {
          "public-key": whisperPublicKey,
          "address": whisperAddress,
          "name": alias,
          "path": PATH_WHISPER,
          "chat": true,
          "derived-from": ""
        }
      ]

      var settingsJson = %* {
        "key-uid": keyUid,
        "public-key": whisperPublicKey,
        "name": alias,
        "display-name": "",
        "address": whisperAddress,
        "eip1581-address": eip1581Address,
        "dapps-address":  walletAddress,
        "wallet-root-address": walletRootAddress,
        "preview-privacy?": true,
        "signing-phrase": generateSigningPhrase(3),
        "log-level": $LogLevel.INFO,
        "latest-derived-path": 0,
        "currency": "usd",
        "networks/networks": @[],
        "networks/current-network": "",
        "wallet/visible-tokens": {},
        "waku-enabled": true,
        "appearance": 0,
        "installation-id": installationId,
        "current-user-status": {
          "publicKey": whisperPublicKey,
          "statusType": 1,
          "clock": 0,
          "text": ""
        }
      }

      self.addKeycardDetails(settingsJson, accountDataJson)
      
      if(accountDataJson.isNil or subaccountDataJson.isNil or settingsJson.isNil or
        nodeConfigJson.isNil):
        let description = "at least one json object is not prepared well"
        error "error: ", procName="setupAccountKeycard", errDesription = description
        return

      self.loggedInAccount = self.saveKeycardAccountAndLogin(chatKey = whisperPrivateKey, 
        password = encryptionPublicKey, 
        accountDataJson, 
        subaccountDataJson, 
        settingsJson, 
        nodeConfigJson)
      self.setLocalAccountSettingsFile()
    except Exception as e:
      error "error: ", procName="setupAccount", errName = e.name, errDesription = e.msg

  proc createAccountFromMnemonic*(self: Service, mnemonic: string, includeEncryption = false, includeWhisper = false,
    includeRoot = false, includeDefaultWallet = false, includeEip1581 = false): GeneratedAccountDto =
    if mnemonic.len == 0:
      error "empty mnemonic"
      return
    var paths: seq[string]
    if includeEncryption:
      paths.add(PATH_ENCRYPTION)
    if includeWhisper:
      paths.add(PATH_WHISPER)
    if includeRoot:
      paths.add(PATH_WALLET_ROOT)
    if includeDefaultWallet:
      paths.add(PATH_DEFAULT_WALLET)
    if includeEip1581:
      paths.add(PATH_EIP_1581)
    try:
      let response = status_account.createAccountFromMnemonicAndDeriveAccountsForPaths(mnemonic, paths)
      return toGeneratedAccountDto(response.result)
    except Exception as e:
      error "error: ", procName="createAccountFromMnemonicAndDeriveAccountsForPaths", errName = e.name, errDesription = e.msg

  proc importMnemonic*(self: Service, mnemonic: string): string =
    if mnemonic.len == 0:
      return "empty mnemonic"
    try:
      let response = status_account.multiAccountImportMnemonic(mnemonic)
      self.importedAccount = toGeneratedAccountDto(response.result)

      if (self.accounts.contains(self.importedAccount.keyUid)):
        return ACCOUNT_ALREADY_EXISTS_ERROR

      let responseDerived = status_account.deriveAccounts(self.importedAccount.id, PATHS)
      self.importedAccount.derivedAccounts = toDerivedAccounts(responseDerived.result)

      self.importedAccount.alias= generateAliasFromPk(self.importedAccount.derivedAccounts.whisper.publicKey)

      if (not self.importedAccount.isValid()):
        return "imported account is not valid"
    except Exception as e:
      error "error: ", procName="importMnemonic", errName = e.name, errDesription = e.msg
      return e.msg

  proc login*(self: Service, account: AccountDto, password: string): string =
    try:
      let hashedPassword = hashString(password)
      var thumbnailImage: string
      var largeImage: string
      for img in account.images:
        if(img.imgType == "thumbnail"):
          thumbnailImage = img.uri
        elif(img.imgType == "large"):
          largeImage = img.uri

      let keyStoreDir = joinPath(main_constants.ROOTKEYSTOREDIR, account.keyUid) & main_constants.sep
      if not dirExists(keyStoreDir):
        os.createDir(keyStoreDir)
        status_core.migrateKeyStoreDir($ %* {
          "key-uid": account.keyUid
        }, password, main_constants.ROOTKEYSTOREDIR, keyStoreDir)

      self.setKeyStoreDir(account.keyUid)
      # This is moved from `status-lib` here
      # TODO:
      # If you added a new value in the nodeconfig in status-go, old accounts will not have this value, since the node config
      # is stored in the database, and it's not easy to migrate using .sql
      # While this is fixed, you can add here any missing attribute on the node config, and it will be merged with whatever
      # the account has in the db
      var nodeCfg = %* {
        "KeyStoreDir": self.keyStoreDir.replace(main_constants.STATUSGODIR, ""),
        "ShhextConfig": %* {
          "BandwidthStatsEnabled": true
        },
        "Web3ProviderConfig": %* {
          "Enabled": true
        },
        "EnsConfig": %* {
          "Enabled": true
        },
        "WalletConfig": {
          "Enabled": true,
          "OpenseaAPIKey": OPENSEA_API_KEY_RESOLVED
        },
        "TorrentConfig": {
          "Enabled": false,
          "DataDir": DEFAULT_TORRENT_CONFIG_DATADIR,
          "TorrentDir": DEFAULT_TORRENT_CONFIG_TORRENTDIR,
          "Port": DEFAULT_TORRENT_CONFIG_PORT
        },
        "Networks": NETWORKS,
        "OutputMessageCSVEnabled": output_csv
      }

      # Source the connection port from the environment for debugging or if default port not accessible
      if existsEnv("STATUS_PORT"):
        let wV1Port = $getEnv("STATUS_PORT")
        # Waku V1 config
        nodeCfg["ListenAddr"] = newJString("0.0.0.0:" & wV1Port)
      if existsEnv("WAKUV2_PORT"):
        let wV2Port = parseInt($getEnv("WAKUV2_PORT"))
        # Waku V2 config
        nodeCfg.add("WakuV2Config", %* {
          "Port": wV2Port,
          "UDPPort": wV2Port,
        })

      if TEST_PEER_ENR != "":
        nodeCfg["Rendezvous"] = newJBool(false)
        nodeCfg["ClusterConfig"] = %* {
          "BootNodes": @[TEST_PEER_ENR],
          "TrustedMailServers": @[TEST_PEER_ENR],
          "StaticNodes": @[TEST_PEER_ENR],
          "RendezvousNodes": @[],
          "DiscV5BootstrapNodes": @[]
        }

      let response = status_account.login(account.name, account.keyUid, account.kdfIterations, hashedPassword, thumbnailImage,
        largeImage, $nodeCfg)
      var error = "response doesn't contain \"error\""
      if(response.result.contains("error")):
        error = response.result["error"].getStr
        if error == "":
          debug "Account logged in"
          self.loggedInAccount = account
          self.setLocalAccountSettingsFile()

      return error

    except Exception as e:
      error "error: ", procName="login", errName = e.name, errDesription = e.msg
      return e.msg

  proc loginAccountKeycard*(self: Service, keycardData: KeycardEvent): string = 
    try:
      self.setKeyStoreDir(keycardData.keyUid)

      let openedAccounts = self.openedAccounts()
      var accToBeLoggedIn: AccountDto
      for acc in openedAccounts:
        if acc.keyUid == keycardData.keyUid:
          accToBeLoggedIn = acc
          break

      var accountDataJson = %* {
        "name": accToBeLoggedIn.name,
        "address": keycardData.masterKey.address,
        "key-uid": keycardData.keyUid
      }
      var settingsJson: JsonNode
      self.addKeycardDetails(settingsJson, accountDataJson)

      let response = status_account.loginWithKeycard(keycardData.whisperKey.privateKey, 
        keycardData.encryptionKey.publicKey,
        accountDataJson)

      var error = "response doesn't contain \"error\""
      if(response.result.contains("error")):
        error = response.result["error"].getStr
        if error == "":
          debug "Account logged in succesfully"
          # this should be fetched later from waku
          self.loggedInAccount = accToBeLoggedIn
          self.loggedInAccount.keycardPairing = accountDataJson{"keycard-pairing"}.getStr
          return
    except Exception as e:
      error "error: ", procName="loginAccountKeycard", errName = e.name, errDesription = e.msg
      return e.msg

  proc verifyAccountPassword*(self: Service, account: string, password: string): bool =
    try:
      let response = status_account.verifyAccountPassword(account, password, self.keyStoreDir)
      if(response.result.contains("error")):
        let errMsg = response.result["error"].getStr
        if(errMsg.len == 0):
          return true
        else:
          error "error: ", procName="verifyAccountPassword", errDesription = errMsg
      return false
    except Exception as e:
      error "error: ", procName="verifyAccountPassword", errName = e.name, errDesription = e.msg


  proc convertToKeycardAccount*(self: Service, keyUid: string, currentPassword: string, newPassword: string) = 
    var accountDataJson = %* {
      "name": self.getLoggedInAccount().name,
      "key-uid": keyUid
    }
    var settingsJson = %* {
      "display-name": self.getLoggedInAccount().name
    }

    self.addKeycardDetails(settingsJson, accountDataJson)
    
    if(accountDataJson.isNil or settingsJson.isNil):
      let description = "at least one json object is not prepared well"
      error "error: ", procName="convertToKeycardAccount", errDesription = description
      return

    let hashedCurrentPassword = hashString(currentPassword)
    let arg = ConvertToKeycardAccountTaskArg(
      tptr: cast[ByteAddress](convertToKeycardAccountTask),
      vptr: cast[ByteAddress](self.vptr),
      slot: "onConvertToKeycardAccount",
      accountDataJson: accountDataJson,
      settingsJson: settingsJson,
      keyStoreDir: self.keyStoreDir,
      hashedCurrentPassword: hashedCurrentPassword,
      newPassword: newPassword
    )
    self.threadpool.start(arg)

  proc onConvertToKeycardAccount*(self: Service, response: string) {.slot.} =
    var result = false
    try:
      let rpcResponse = Json.decode(response, RpcResponse[JsonNode])
      if(rpcResponse.result.contains("error")):
        let errMsg = rpcResponse.result["error"].getStr
        if(errMsg.len == 0):
          result = true
        else:
          error "error: ", procName="convertToKeycardAccount", errDesription = errMsg
    except Exception as e:
      error "error handilng migrated keypair response", errDesription=e.msg
    self.events.emit(SIGNAL_CONVERTING_PROFILE_KEYPAIR, ResultArgs(success: result))

  proc verifyPassword*(self: Service, password: string): bool =
    try:
      let hashedPassword = hashString(password)
      let response = status_account.verifyPassword(hashedPassword)
      return response.result.getBool
    except Exception as e:
      error "error: ", procName="verifyPassword", errName = e.name, errDesription = e.msg
    return false