package manifests

import (
	"testing"

	"github.com/github/dependency-snapshots-api/internal/ecosystems"
	"github.com/stretchr/testify/require"
)

func TestClassifyManifest_PythonManifests(t *testing.T) {
	tests := []struct {
		name             string
		filePath         string
		expectedFound    bool
		expectedPath     string
		expectedName     string
		expectedEco      ecosystems.Ecosystem
		expectedFileType FileType
	}{
		{
			name:             "Pipfile at root",
			filePath:         "Pipfile",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "Pipfile",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: Pipfile,
		},
		{
			name:             "Pipfile in subdirectory",
			filePath:         "backend/Pipfile",
			expectedFound:    true,
			expectedPath:     "backend",
			expectedName:     "Pipfile",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: Pipfile,
		},
		{
			name:             "Pipfile.lock at root",
			filePath:         "Pipfile.lock",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "Pipfile.lock",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: PipfileLock,
		},
		{
			name:             "Pipfile.lock in subdirectory",
			filePath:         "services/web/Pipfile.lock",
			expectedFound:    true,
			expectedPath:     "services/web",
			expectedName:     "Pipfile.lock",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: PipfileLock,
		},
		{
			name:             "setup.py at root",
			filePath:         "setup.py",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "setup.py",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: SetupPy,
		},
		{
			name:             "setup.py in subdirectory",
			filePath:         "libs/mylib/setup.py",
			expectedFound:    true,
			expectedPath:     "libs/mylib",
			expectedName:     "setup.py",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: SetupPy,
		},
		{
			name:             "pyproject.toml at root",
			filePath:         "pyproject.toml",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "pyproject.toml",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: PyprojectToml,
		},
		{
			name:             "pyproject.toml in subdirectory",
			filePath:         "packages/core/pyproject.toml",
			expectedFound:    true,
			expectedPath:     "packages/core",
			expectedName:     "pyproject.toml",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: PyprojectToml,
		},
		{
			name:             "poetry.lock at root",
			filePath:         "poetry.lock",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "poetry.lock",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: PoetryLock,
		},
		{
			name:             "poetry.lock in subdirectory",
			filePath:         "apps/frontend/poetry.lock",
			expectedFound:    true,
			expectedPath:     "apps/frontend",
			expectedName:     "poetry.lock",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: PoetryLock,
		},
		{
			name:             "case insensitive Pipfile",
			filePath:         "PIPFILE",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "PIPFILE",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: Pipfile,
		},
		{
			name:             "case insensitive pyproject.toml",
			filePath:         "PYPROJECT.TOML",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "PYPROJECT.TOML",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: PyprojectToml,
		},
		{
			name:             "uv.lock at root",
			filePath:         "uv.lock",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "uv.lock",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: UvLock,
		},
		{
			name:             "uv.lock in subdirectory",
			filePath:         "services/api/uv.lock",
			expectedFound:    true,
			expectedPath:     "services/api",
			expectedName:     "uv.lock",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: UvLock,
		},
		{
			name:             "uv.lock case insensitive",
			filePath:         "UV.LOCK",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "UV.LOCK",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: UvLock,
		},
		{
			name:             "requirements.txt at root",
			filePath:         "requirements.txt",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "requirements.txt",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},
		{
			name:             "requirements.txt in subdirectory",
			filePath:         "backend/requirements.txt",
			expectedFound:    true,
			expectedPath:     "backend",
			expectedName:     "requirements.txt",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},
		{
			name:             "requirements.txt case insensitive",
			filePath:         "REQUIREMENTS.TXT",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "REQUIREMENTS.TXT",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},

		// requirements.txt regex variants (REQUIREMENTS_TXT_PATTERN)
		{
			name:             "requirements slash-separated variant",
			filePath:         "requirements/production.txt",
			expectedFound:    true,
			expectedPath:     "requirements",
			expectedName:     "production.txt",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},
		{
			name:             "requirements dot-separated variant",
			filePath:         "requirements.prod.txt",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "requirements.prod.txt",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},
		{
			name:             "requirements hyphen-separated variant",
			filePath:         "requirements-dev.txt",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "requirements-dev.txt",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},
		{
			name:             "requirements underscore-separated variant",
			filePath:         "requirements_test.txt",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "requirements_test.txt",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},
		{
			name:             "requirements variant in subdirectory",
			filePath:         "config/requirements.prod.txt",
			expectedFound:    true,
			expectedPath:     "config",
			expectedName:     "requirements.prod.txt",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},
		{
			name:             "hyphen-prefixed requirements variant",
			filePath:         "dev-requirements.txt",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "dev-requirements.txt",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},
		{
			name:             "dot-prefixed requirements variant",
			filePath:         "test.requirements.txt",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "test.requirements.txt",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},
		{
			name:             "underscore-prefixed requirements variant",
			filePath:         "base_requirements.txt",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "base_requirements.txt",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},

		// requirements.txt regex variants (REQUIRE_TXT_PATTERN)
		{
			name:             "require.txt short form",
			filePath:         "require.txt",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "require.txt",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},
		{
			name:             "require-test.txt short form with suffix",
			filePath:         "require-test.txt",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "require-test.txt",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},
		{
			name:             "py3-require.txt prefix with short form",
			filePath:         "py3-require.txt",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "py3-require.txt",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},
		{
			name:             "pyenv_require_e2e.txt underscore prefix variant",
			filePath:         "pyenv_require_e2e.txt",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "pyenv_require_e2e.txt",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},
		{
			name:             "require.txt in subdirectory",
			filePath:         "deps/require.txt",
			expectedFound:    true,
			expectedPath:     "deps",
			expectedName:     "require.txt",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},
		{
			name:             "require variant case insensitive",
			filePath:         "REQUIRE-TEST.TXT",
			expectedFound:    true,
			expectedPath:     ".",
			expectedName:     "REQUIRE-TEST.TXT",
			expectedEco:      ecosystems.PyPi,
			expectedFileType: RequirementsTxt,
		},

		// Negative cases for requirements.txt regex
		{
			name:          "required.txt should not match",
			filePath:      "required.txt",
			expectedFound: false,
		},
		{
			name:          "requirements.md wrong extension",
			filePath:      "requirements.md",
			expectedFound: false,
		},
		{
			name:          "README.txt unrelated txt file",
			filePath:      "README.txt",
			expectedFound: false,
		},
		{
			name:          "non-manifest file",
			filePath:      "main.py",
			expectedFound: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			info, found := ClassifyManifest(tt.filePath)
			require.Equal(t, tt.expectedFound, found)
			if found {
				require.Equal(t, tt.expectedPath, info.Path)
				require.Equal(t, tt.expectedName, info.Name)
				require.Equal(t, tt.expectedEco, info.Ecosystem)
				require.Equal(t, tt.expectedFileType, info.FileType)
				require.False(t, info.IsPreview)
			}
		})
	}
}
