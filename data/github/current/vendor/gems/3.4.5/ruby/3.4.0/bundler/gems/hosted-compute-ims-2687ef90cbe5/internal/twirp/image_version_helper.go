package twirp

import (
	"context"
	"strconv"
	"strings"

	"github.com/Masterminds/semver"
	"github.com/twitchtv/twirp"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
)

// Every way I can think to simplify this results in more complexity overall.
//
//nolint:gocognit
func (h *baseApiHandler) getNextImageVersionAsNeeded(ctx context.Context, imageDefinitionId uint64, version string) (string, error) {
	ctx = stash.WithLoggingFields(ctx, kvp.Uint64("image_definition_id", imageDefinitionId))

	if version != "" && !strings.Contains(version, "*") {
		_, err := semver.NewVersion(version)
		if err != nil {
			logger.ErrorWithReport(ctx, "invalid image version format", err, kvp.String("image_version", version))
			return "", twirp.InvalidArgument.Error("invalid image version format")
		}

		return version, nil
	}

	// Version: <major>.<minor>.<patch>
	existingImageVersions, err := h.imageStore.ListImageVersionsByDefinitionId(ctx, imageDefinitionId)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to list image versions for image definition", err)
		return "", twirp.Internal.Error("failed to auto-increment image version")
	}

	models.SortImageVersionsByVersion(existingImageVersions)
	minVersion := strings.Replace(version, "*", "0", 3)
	if minVersion == "" {
		minVersion = "1.0.0"
	}

	latestVersion, err := semver.NewVersion(minVersion)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to parse minimum image version", err, kvp.String("image_version", minVersion))
		return "", twirp.Internal.Error("failed to auto-increment image version")
	}

	if version == "" {
		// If image version is not specified at all, take the last image version 1.5.0 and increment minor version (to 1.6.0)
		if len(existingImageVersions) > 0 {
			latestVersion, err = semver.NewVersion(existingImageVersions[0].Version)
			if err != nil {
				logger.ErrorWithReport(ctx, "failed to parse latest image version", err, kvp.String("image_version", existingImageVersions[0].Version))
				return "", twirp.Internal.Error("failed to auto-increment image version")
			}

			v := latestVersion.IncMinor()
			return v.String(), nil
		}

		return latestVersion.String(), nil
	}

	versionSplit := strings.Split(version, ".")

	if len(versionSplit) > 3 || len(versionSplit) <= 1 {
		logger.Info(ctx, "invalid image version format", kvp.String("image_version", version))
		return "", twirp.InvalidArgument.Error("invalid image version format")
	}

	// If input is 1.*.*, increment patch version of 1.<highest-minor>
	// If input is 1.5.*, increment patch version of 1.5.0 -> 1.5.1
	wildcardPatch := len(versionSplit) == 3 && versionSplit[2] == "*"

	// If input is 1.*.*, increment patch version of 1.<highest-minor>
	// If input is 1.*, increment minor version 1.5.0 -> 1.6.0
	wildcardMinor := versionSplit[1] == "*"

	majorVersion, err := strconv.ParseInt(versionSplit[0], 10, 0)
	if err != nil {
		logger.Info(ctx, "invalid major version format", kvp.String("image_version", version))
		return "", twirp.InvalidArgument.Error("invalid major version format")
	}

	var minorVersion int64 = 0
	if !wildcardMinor {
		minorVersion, err = strconv.ParseInt(versionSplit[1], 10, 0)
		if err != nil {
			logger.Info(ctx, "invalid minor version format", kvp.String("image_version", version))
			return "", twirp.InvalidArgument.Error("invalid minor version format")
		}
	}

	for _, latestImageVersion := range existingImageVersions {
		currentVersion, err := semver.NewVersion(latestImageVersion.Version)
		if err != nil {
			logger.ErrorWithReport(ctx, "failed to parse known image version", err, kvp.String("image_version", latestImageVersion.Version))
			return "", twirp.Internal.Error("failed to auto-increment image version")
		}

		// Check major version
		if currentVersion.Major() > majorVersion {
			// We're still attempting to move down to the correct major version.
			continue
		} else if currentVersion.Major() < majorVersion {
			// We've gone past the expected major version and we should use the default.
			break
		}

		// We have the correct major version; check minor version
		if wildcardMinor {
			if wildcardPatch {
				// If input is 1.*.*, increment patch version of 1.<highest-minor>
				v := currentVersion.IncPatch()
				return v.String(), nil
			} else {
				// If input is 1.*, increment minor version 1.5.0 -> 1.6.0
				v := currentVersion.IncMinor()
				return v.String(), nil
			}
		} else {
			if currentVersion.Minor() > minorVersion {
				// We're still attempting to move down to the correct minor version.
				continue
			} else if currentVersion.Minor() < minorVersion {
				// We've gone past the expected major version and we should use the default.
				break
			}

			// We have the correct major and minor versions. Increment patch and return.
			// If input is 1.5.*, increment patch version of 1.5.0 -> 1.5.1
			v := currentVersion.IncPatch()
			return v.String(), nil
		}
	}

	return latestVersion.String(), nil
}
