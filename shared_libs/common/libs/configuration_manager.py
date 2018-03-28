class ConfigurationManager(object):

    @staticmethod
    def getStepConfiguration(stepName):
        return {}

    @staticmethod
    def _merge(params, paramKeys, defaults):
        merged = dict(defaults)
        for key in paramKeys:
            if key in params:
                merged[key] = params[key]
        return merged

    @staticmethod
    def mergeData(params, paramKeys, defaults,
                  config, configKeys):
        merged = ConfigurationManager._merge(config, configKeys, defaults)
        merged = ConfigurationManager._merge(params, paramKeys, merged)
        return merged
