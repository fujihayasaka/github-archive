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
