import subprocess


class Utils(object):

    @staticmethod
    def doCommand(cmd):
        output = subprocess.check_output(cmd, shell=True)
        print(output)
        return output.strip()

    @staticmethod
    def getGitCommitId():
        return Utils.doCommand("git rev-parse HEAD")
