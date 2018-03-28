from shared_libs.common.libs.callable import Callable
from shared_libs.common.libs.artifact_version import ArtifactVersion
from shared_libs.common.libs.utils import Utils
from shared_libs.common.libs.configuration_manager import ConfigurationManager
from zope import component
from zope import interface


@interface.implementer(Callable)
class ArtifactSetVersion(object):

    def __init__(self):
        pass

    def call(self, params):

        stepConfiguration = ConfigurationManager.getStepConfiguration(self.getStepName())
        configuration = ConfigurationManager.mergeData(params,
                                                       self.getParameterKeys(),
                                                       self.getDefaultKeyValues(),
                                                       stepConfiguration,
                                                       self.getStepKeys())
        artifactVersion = component.getUtility(ArtifactVersion, 'artifactversion')
        print("Artifact version is %s" % (artifactVersion.getVersion()))

    def getParameterKeys(self):
        return [
                'buildTool',
                'gitCommitId'
                'gitUserEMail',
                'gitUserName',
                'timestamp',
                'timestampTemplate',
                'versioningTemplate'
                ]

    def getDefaultKeyValues(self):
        return {
            'gitCommitId': Utils.getGitCommitId()
        }

    def getStepName(self):
        "artifactSetVersion"

    def getStepKeys(self):
        return self.getParameterKeys()
