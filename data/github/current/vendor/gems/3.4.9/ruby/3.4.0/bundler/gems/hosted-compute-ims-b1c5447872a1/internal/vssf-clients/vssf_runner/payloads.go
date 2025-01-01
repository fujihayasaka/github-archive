package vssf_runner

// Runner owns the contract
//
//nolint:tagliatelle
type ImageUsage struct {
	ImageVersions map[string]ImageVersionUsage `json:"image_versions"`
}

// Runner owns the contract
//
//nolint:tagliatelle
type ImageVersionUsage struct {
	VMCountPerRegion map[string]int32 `json:"vmcount_per_region"`
}

func MergeImagesUsage(firstImageUsage *ImageUsage, otherImagesUsage ...*ImageUsage) *ImageUsage {
	mergedImagesUsage := firstImageUsage
	if mergedImagesUsage.ImageVersions == nil {
		mergedImagesUsage.ImageVersions = make(map[string]ImageVersionUsage)
	}

	for _, imageUsage := range otherImagesUsage {
		for version, imageVersionCount := range imageUsage.ImageVersions {
			if existingUsage, ok := mergedImagesUsage.ImageVersions[version]; !ok {
				mergedImagesUsage.ImageVersions[version] = imageVersionCount
			} else {
				// Add up the VM counts
				for region, count := range imageVersionCount.VMCountPerRegion {
					existingUsage.VMCountPerRegion[region] += count
				}
			}
		}
	}

	return mergedImagesUsage
}
