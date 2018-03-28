import configparser
try:
    from StringIO import StringIO
except ImportError:
    from io import StringIO
from contextlib import closing
from shared_libs.common.libs.artifact_version import ArtifactVersion
from zope import interface


@interface.implementer(ArtifactVersion)
class RPMArtifactVersion(object):

    def __init__(self):
        self.properties_file = 'build.properties'

    def _get_properties(self):
        key_name = 'Default'
        section_name = '[%s]' % (key_name)
        config_string = ''
        with open(self.properties_file, 'r') as f:
            config_string = section_name + '\n' + f.read()
        config = configparser.RawConfigParser()
        config.optionxform = str
        config.read_string(config_string)
        return config._sections[key_name]

    def _set_properties(self, config_properties):
        key_name = 'Default'
        section_name = '[%s]' % (key_name)
        config = configparser.RawConfigParser()
        config.optionxform = str
        config[key_name] = config_properties

        output = ''
        with closing(StringIO()) as sio:
            config.write(sio)
            output = sio.getvalue()

        output = output.replace(section_name + "\n", '', 1)
        with open(self.properties_file, 'w') as f:
            f.write(output)

    def getVersion(self):
        properties = self._get_properties()
        return "%s-%s" % (properties['VERSION'],
                          properties['RELEASE'])

    def setVersion(self, version):
        config_properties = self._get_properties()
        version_split = version.split('-')
        if len(version_split) != 2:
            raise ValueError("Expecting version of VERSION-RELEASE")
        config_properties['VERSION'] = version_split[0]
        config_properties['RELEASE'] = version_split[1]
        self._set_properties(self, config_properties)
