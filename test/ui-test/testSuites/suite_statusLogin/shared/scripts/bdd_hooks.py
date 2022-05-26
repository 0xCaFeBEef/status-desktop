# -*- coding: utf-8 -*-
# This file contains hook functions to run as the .feature file is executed.


from utils.FileManager import *

sys.path.append(os.path.join(os.path.dirname(__file__), "../../../src/"))


_statusDektopAppName = "nim_status_client"
_appClosureTimeout = 2 #[seconds]

@OnScenarioStart
def hook(context):
    erase_directory("../../../../../Status/data")
    startApplication(_statusDektopAppName)
    context.userData = {}

@OnScenarioEnd
def hook(context):
    currentApplicationContext().detach()
    snooze(_appClosureTimeout)

