from zope import interface


class Callable(interface.Interface):

    def call(self, params):
        pass

    def getParameterKeys(self):
        pass

    def getDefaultKeyValues(self):
        pass

    def getStepKeys(self):
        pass

    def getStepName(self):
        pass
