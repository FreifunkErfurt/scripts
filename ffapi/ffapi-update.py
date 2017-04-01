#!/usr/bin/env python2
# -*- coding: utf-8 -*-
#
# This script can be used to dynamically update our ffapi-json-file with
# the number of currently running nodes.
#
# The number of running nodes is received by getting nodes.json from the map.
#
# Based on ffapi-update-nodes.py quickly hacked together by soma
# (freifunk at somakoma dot de) and released into the public domain.
#
# Version: 0.2

import os
import json
import datetime
import time
import urllib2
import config

# Configuration - replace these variables with your settings

response = urllib2.urlopen(config.BASE_URL + '/nodes.json')
node_list = json.loads(response.read().decode('UTF-8'))
response = urllib2.urlopen(config.MESHVIEWER_NODES_URL)
meshviewer_node_list = json.loads(response.read().decode('UTF-8'))

# End of configuration


def gluonNodes():
    """ Count clients and nodes """
    clients = 0
    nodes = 0

    for node in node_list['nodes']:
        site_code = ''
        node_id = node['id'].replace(':', '')
        if config.SITE_CODE != site_code and node_id in meshviewer_node_list['nodes']:
            site_code = meshviewer_node_list['nodes'][node_id]['nodeinfo']['system']['site_code']
        if node['flags']['online'] and config.SITE_CODE == site_code:
            nodes += 1
            clients += node['clientcount']

    return nodes


def loadApiTemplateFile():
    """ Load an api file into a dictionary """
    if not os.access(config.API_FILE_TEMPLATE, os.R_OK):
        print 'Error: Could not read %(file)s.' \
            % {"file": config.API_FILE_TEMPLATE}
        print 'Make sure the path is correct and your user has' + \
            'read and write permissions.'
        exit()
    with open(config.API_FILE_TEMPLATE, 'r') as ffapi:
        apidict = json.load(ffapi)
        ffapi.closed
    return apidict


def updateApiNodes(apiDict, countNodes):
    """ Updates an ffapi dictionary with number of nodes and timestamp """
    try:
        apiDict['state']['nodes'] = countNodes
    except KeyError:
        print 'Could not update %(field)s in the ffapi dictionary.' \
            % {"field": "['state']['nodes']"}

    try:
        apiDict['state']['lastchange'] = datetime.datetime.now().isoformat()
    except KeyError:
        print 'Could not update %(field)s in the ffapi dictionary.' \
            % {"field": "['state']['lastchange']"}
    return apiDict


def writeApiFile(content):
    """ writes the dictionary to the ffapi json file """
    if not os.access(config.API_FILE, os.W_OK):
        print 'Error: Could not write %(file)s.' % {"file": config.API_FILE}
        print 'Make sure the path is correct and your user has write ' + \
            'permissions for it.'
        exit()

    with open(config.API_FILE, 'w') as ffapi:
        ffapi.write(json.dumps(content, indent=4))
    return True


def main():
    countNodes = gluonNodes()
    apiDict = loadApiTemplateFile()
    apiDictUpdated = updateApiNodes(apiDict, countNodes)

    if writeApiFile(apiDictUpdated):
        print('Update of %s successful.' % config.API_FILE)
        print('We now have %d Nodes' % countNodes)

if __name__ == "__main__":
    main()
