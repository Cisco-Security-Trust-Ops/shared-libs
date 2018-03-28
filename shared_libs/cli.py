#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""Console script for shared_libs."""
import sys
import click
import logging

from shared_libs.common.artifact_setversion import ArtifactSetVersion

from shared_libs.common.libs.callable import Callable
from shared_libs.common.libs.artifact_version import ArtifactVersion
from shared_libs.rpm.rpm_version import RPMArtifactVersion

from zope import component


def main(args=None):
    registerCallables()
    registerRPMComponents()
    logging.getLogger().setLevel(logging.DEBUG)
    command = args[1]
    parameters = dict([arg.split('=', maxsplit=1) for arg in args[2:]])
    logging.debug("Received command %s with params %s" % (command, parameters))
    component.getUtility(Callable, command).call(parameters)

    return 0


def registerCallables():
    component.provideUtility(ArtifactSetVersion(),
                             Callable,
                             'artifactSetVersion')


def registerRPMComponents():
    component.provideUtility(RPMArtifactVersion(),
                             ArtifactVersion,
                             'artifactversion')


if __name__ == "__main__":
    sys.exit(main(sys.argv[0:]))  # pragma: no cover
