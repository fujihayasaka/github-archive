package largerrunners

import (
	"github.com/golang/protobuf/ptypes/wrappers"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/pkg/azp"
)

func (s *service) mapRunnerPool(runnerPool *azp.RunnerPool) *Pool {
	rp := &Pool{
		Id:                     runnerPool.ID,
		Name:                   runnerPool.Name,
		Platform:               runnerPool.Platform,
		RunnerGroupId:          runnerPool.RunnerGroupID,
		GroupName:              runnerPool.GroupName,
		Inherited:              runnerPool.Inherited,
		Labels:                 runnerPool.Labels,
		Ephemeral:              runnerPool.Ephemeral,
		RunnerCount:            runnerPool.RunnerCount,
		IsDev:                  runnerPool.IsDev,
		MachineSpecId:          runnerPool.MachineSpecID,
		MachineSpec:            s.mapMachineSpec(&runnerPool.MachineSpec),
		LastActiveOn:           runnerPool.LastActiveOn,
		MaximumRunners:         runnerPool.MaximumRunners,
		UnavailableRunnerCount: runnerPool.UnavailableRunnerCount,
		PersistentOsDisk:       runnerPool.PersistentOSDisk,
		ErrorCode:              runnerPool.ErrorCode,
		PublicIpEnabled:        runnerPool.PublicIPEnabled,
	}
	rp.State = stringToPoolStateMap[runnerPool.State]

	rp.Image = s.mapImageKey(&runnerPool.Image)
	rp.PublicIps = s.mapPublicIPs(runnerPool)
	return rp
}

func (s *service) mapRunnerPools(ars []*azp.RunnerPool) []*Pool {
	rps := make([]*Pool, 0, len(ars))
	for _, ar := range ars {
		rp := s.mapRunnerPool(ar)
		rps = append(rps, rp)
	}

	return rps
}

var stringToPoolStateMap = map[string]PoolState{
	"Provisioning":    PoolState_Provisioning,
	"Resetting":       PoolState_Provisioning,
	"Ready":           PoolState_Ready,
	"Deleting":        PoolState_Deleting,
	"Stuck":           PoolState_Stuck,
	"ShutdownBilling": PoolState_ShutdownBilling,
	"ShutdownSpammy":  PoolState_ShutdownSpammy,
	"ShutdownNetwork": PoolState_ShutdownNetwork,
}

var stringToImageSource = map[string]ImageKey_ImageSource{
	"Marketplace": ImageKey_Marketplace,
	"Enterprise":  ImageKey_Enterprise,
	"Curated":     ImageKey_Curated,
	"Custom":      ImageKey_Custom,
}

var imageSourceToString = map[ImageKey_ImageSource]string{
	ImageKey_Marketplace: "Marketplace",
	ImageKey_Enterprise:  "Enterprise",
	ImageKey_Curated:     "Curated",
	ImageKey_Custom:      "Custom",
}

func (s *service) mapImageKey(azpImageKey *azp.ImageKey) *ImageKey {
	return &ImageKey{
		Source:  stringToImageSource[azpImageKey.Source],
		Id:      azpImageKey.ID,
		Version: azpImageKey.Version,
	}
}

var platformToOsType = map[string]string{
	"linux-x64": "Linux",
	"win-x64":   "Windows",
}

func (s *service) mapPublicIP(publicIP azp.PublicIP) *PublicIP {
	return &PublicIP{
		Enabled: publicIP.Enabled,
		Prefix:  publicIP.Prefix,
		Length:  publicIP.Length,
	}
}

func (s *service) mapPublicIPs(runnerPool *azp.RunnerPool) []*PublicIP {
	ips := make([]*PublicIP, 0, len(runnerPool.PublicIPs))
	for _, ar := range runnerPool.PublicIPs {
		ip := s.mapPublicIP(ar)
		ips = append(ips, ip)
	}

	return ips
}

func (s *service) mapMachineSpec(machineSpec *azp.MachineSpec) *MachineSpec {
	return &MachineSpec{
		Id:               machineSpec.ID,
		CpuCores:         machineSpec.CPUCores,
		MemoryGb:         machineSpec.MemoryGB,
		StorageGb:        machineSpec.StorageGB,
		Type:             machineSpec.Type,
		DocumentationUrl: machineSpec.DocumentationURL,
		Gpu:              s.mapMachineSpecGpu(machineSpec.GPU),
		Architecture:     machineSpec.Architecture,
	}
}

func (s *service) mapMachineSpecGpu(machineSpecGpu *azp.MachineSpecGpu) *MachineSpecGpu {
	if machineSpecGpu == nil {
		return nil
	}
	return &MachineSpecGpu{
		Name:     machineSpecGpu.Name,
		Count:    machineSpecGpu.Count,
		MemoryGb: machineSpecGpu.MemoryGB,
	}
}

func (s *service) mapMachineSpecs(ars []*azp.MachineSpec) []*MachineSpec {
	rps := make([]*MachineSpec, 0, len(ars))
	for _, ar := range ars {
		rp := s.mapMachineSpec(ar)
		rps = append(rps, rp)
	}

	return rps
}

func (s *service) mapImage(image *azp.Image) *Image {
	return &Image{
		Id:          image.ID,
		DisplayName: image.DisplayName,
		SizeGb:      image.SizeGB,
		Platform:    image.Platform,
	}
}

func (s *service) mapImages(images []*azp.Image) []*Image {
	rps := make([]*Image, 0, len(images))
	for _, ar := range images {
		rp := s.mapImage(ar)
		rps = append(rps, rp)
	}

	return rps
}

var stringToImageDefinitionOsTypeMap = map[string]ImageDefinition_OsType{
	"Linux":   ImageDefinition_Linux,
	"Windows": ImageDefinition_Windows,
}

var stringToImageDefinitionStateMap = map[string]ImageDefinition_ImageDefinitionState{
	"Provisioning": ImageDefinition_Provisioning,
	"Ready":        ImageDefinition_Ready,
	"Deleting":     ImageDefinition_Deleting,
}

func (s *service) mapImageDefinition(imageDefinition *azp.ImageDefinition) *ImageDefinition {
	if imageDefinition == nil {
		return nil
	}

	var latestVersion *wrappers.StringValue
	if imageDefinition.ImageDefinitionLatestVersion != nil {
		latestVersion = &wrappers.StringValue{Value: *imageDefinition.ImageDefinitionLatestVersion}
	}

	return &ImageDefinition{
		Id:                imageDefinition.ID,
		Name:              imageDefinition.Name,
		OsType:            stringToImageDefinitionOsTypeMap[imageDefinition.OsType],
		State:             stringToImageDefinitionStateMap[imageDefinition.ImageDefinitionState],
		VersionCount:      imageDefinition.ImageDefinitionVersionCount,
		TotalVersionsSize: imageDefinition.ImageDefinitionTotalVersionsSize,
		LatestVersion:     latestVersion,
		Platform:          imageDefinition.Platform,
	}
}

func (s *service) mapImageDefinitions(definitions []*azp.ImageDefinition) []*ImageDefinition {
	defs := make([]*ImageDefinition, 0, len(definitions))
	for _, def := range definitions {
		d := s.mapImageDefinition(def)
		defs = append(defs, d)
	}

	return defs
}

var stringToimageVersionStateMap = map[string]ImageVersion_ImageState{
	"ImportingBlob":            ImageVersion_ImportingBlob,
	"ProvisioningImageVersion": ImageVersion_ProvisioningImageVersion,
	"Ready":                    ImageVersion_Ready,
	"ImportFailed":             ImageVersion_ImportFailed,
	"Deleting":                 ImageVersion_Deleting,
	"Generating":               ImageVersion_Generating,
}

var stringtoImageFailureMap = map[string]ImageVersion_FailureReason{
	"AuthenticationFailed": ImageVersion_AuthenticationFailed,
	"InvalidSasUri":        ImageVersion_InvalidSasUri,
	"ResourceNotFound":     ImageVersion_ResourceNotFound,
	"InvalidVirtualDisk":   ImageVersion_InvalidVirtualDisk,
}

func (s *service) mapImageVersion(imageVersion *azp.ImageVersion) *ImageVersion {
	if imageVersion == nil {
		return nil
	}

	var size *wrappers.Int32Value
	if imageVersion.ImageVersionSize != nil {
		size = &wrappers.Int32Value{Value: *imageVersion.ImageVersionSize}
	}

	var lastUsedOn *wrappers.StringValue
	if imageVersion.ImageVersionLastUsedOn != nil {
		lastUsedOn = &wrappers.StringValue{Value: *imageVersion.ImageVersionLastUsedOn}
	}

	return &ImageVersion{
		Version:       imageVersion.Version,
		State:         stringToimageVersionStateMap[imageVersion.ImageVersionState],
		FailureReason: stringtoImageFailureMap[imageVersion.ImageVersionImportFailureReason],
		CreatedOn:     timestamppb.New(imageVersion.ImageVersionCreatedOn),
		Size:          size,
		LastUsedOn:    lastUsedOn,
	}
}

func (s *service) mapImageVersions(ars []*azp.ImageVersion) []*ImageVersion {
	rps := make([]*ImageVersion, 0, len(ars))
	for _, ar := range ars {
		rp := s.mapImageVersion(ar)
		rps = append(rps, rp)
	}

	return rps
}

func (s *service) mapBetaFeature(feature *azp.BetaFeature) *BetaFeature {
	return &BetaFeature{
		Name:            feature.Name,
		EnabledForUser:  feature.EnabledForUser,
		EnabledGlobally: feature.EnabledGlobally,
	}
}

func (s *service) mapBetaFeatures(ars []*azp.BetaFeature) []*BetaFeature {
	rps := make([]*BetaFeature, 0, len(ars))
	for _, ar := range ars {
		rp := s.mapBetaFeature(ar)
		rps = append(rps, rp)
	}

	return rps
}
