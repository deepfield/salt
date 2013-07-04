# Import Salt Testing libs
from salttesting import skipIf, TestCase
from salttesting.helpers import ensure_in_syspath
ensure_in_syspath('../../')

# Import salt libs
from salt.modules import pip

try:
    from mock import MagicMock, patch
    has_mock = True
except ImportError:
    has_mock = False
    patch = lambda x: lambda y: None


pip.__salt__ = {'cmd.which_bin': lambda _: 'pip'}


@skipIf(has_mock is False, 'mock python module is unavailable')
class PipTestCase(TestCase):

    def test_fix4361(self):
        mock = MagicMock(return_value={'retcode': 0, 'stdout': ''})
        with patch.dict(pip.__salt__, {'cmd.run_all': mock}):
            pip.install(requirements='requirements.txt')
            expected_cmd = 'pip install --requirement=\'requirements.txt\''
            mock.assert_called_once_with(expected_cmd, runas=None, cwd=None)

    def test_issue5940_multiple_pip_mirrors(self):
        mirrors = [
            'http://g.pypi.python.org',
            'http://c.pypi.python.org',
            'http://pypi.crate.io'
        ]

        # Passing mirrors as a list
        mock = MagicMock(return_value={'retcode': 0, 'stdout': ''})
        with patch.dict(pip.__salt__, {'cmd.run_all': mock}):
            pip.install(mirrors=mirrors)
            mock.assert_called_once_with(
                'pip install --use-mirrors '
                '--mirrors=http://g.pypi.python.org '
                '--mirrors=http://c.pypi.python.org '
                '--mirrors=http://pypi.crate.io',
                runas=None,
                cwd=None
            )

        # Passing mirrors as a comma separated list
        mock = MagicMock(return_value={'retcode': 0, 'stdout': ''})
        with patch.dict(pip.__salt__, {'cmd.run_all': mock}):
            pip.install(mirrors=','.join(mirrors))
            mock.assert_called_once_with(
                'pip install --use-mirrors '
                '--mirrors=http://g.pypi.python.org '
                '--mirrors=http://c.pypi.python.org '
                '--mirrors=http://pypi.crate.io',
                runas=None,
                cwd=None
            )

    @patch('salt.modules.pip._get_cached_requirements')
    def test_failed_cached_requirements(self, get_cached_requirements):
        get_cached_requirements.return_value = False
        ret = pip.install(requirements='salt://my_test_reqs')
        self.assertEqual(False, ret['result'])
        self.assertIn('my_test_reqs', ret['comment'])

    @patch('salt.modules.pip._get_cached_requirements')
    def test_cached_requirements_used(self, get_cached_requirements):
        get_cached_requirements.return_value = 'my_cached_reqs'
        mock = MagicMock(return_value={'retcode': 0, 'stdout': ''})
        with patch.dict(pip.__salt__, {'cmd.run_all': mock}):
            pip.install(requirements='salt://requirements.txt')
            expected_cmd = 'pip install --requirement=\'my_cached_reqs\''
            mock.assert_called_once_with(expected_cmd, runas=None, cwd=None)

    @patch('os.path')
    def test_fix_activate_env(self, mock_path):
        mock_path.is_file.return_value = True
        mock_path.isdir.return_value = True

        def join(*args):
            return '/'.join(args)
        mock_path.join = join
        mock = MagicMock(return_value={'retcode': 0, 'stdout': ''})
        with patch.dict(pip.__salt__, {'cmd.run_all': mock}):
            pip.install('mock', bin_env='/test_env', activate=True)
            mock.assert_called_once_with(
                '. /test_env/bin/activate && /test_env/bin/pip install mock',
                runas=None,
                cwd=None)


if __name__ == '__main__':
    from integration import run_tests
    run_tests(PipTestCase, needs_daemon=False)
