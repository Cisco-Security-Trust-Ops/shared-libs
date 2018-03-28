from zope import interface


class ArtifactVersion(interface.Interface):

    def getVersion(self):
        pass

    def setVersion(self, version):
        pass
