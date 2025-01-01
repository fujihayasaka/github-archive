package models

type (
	ImageDefinitionState string
	ImageVersionState    string
	OsType               string
	ImageType            string
	Architecture         string
	VmGeneration         string
	OsState              string
)

const (
	GithubOwnerId      = "github"
	PartnerOwnerId     = "partner"
	AzureDevOpsOwnerId = "azuredevops"
	LatestImageVersion = "latest"
)

var AllowedCuratedImagesOwners = []string{GithubOwnerId, PartnerOwnerId, AzureDevOpsOwnerId}

const (
	ImageDefinitionState_Ready    ImageDefinitionState = "Ready"
	ImageDefinitionState_Deleting ImageDefinitionState = "Deleting"
)

const (
	ImageVersionState_Pending         ImageVersionState = "Pending"
	ImageVersionState_Provisioning    ImageVersionState = "Provisioning"
	ImageVersionState_Ready           ImageVersionState = "Ready"
	ImageVersionState_ProvisionFailed ImageVersionState = "ProvisionFailed"
	ImageVersionState_Deleting        ImageVersionState = "Deleting"
	ImageVersionState_Generating      ImageVersionState = "Generating"
)

const (
	OsType_Linux   OsType = "Linux"
	OsType_Windows OsType = "Windows"
	OsType_MacOS   OsType = "MacOS"
)

const (
	ImageType_Curated  ImageType = "Curated"
	ImageType_Customer ImageType = "Customer"
)

const (
	Architecture_X64   Architecture = "X64"
	Architecture_Arm64 Architecture = "Arm64"
)

const (
	VmGeneration_Gen1 VmGeneration = "Gen1"
	VmGeneration_Gen2 VmGeneration = "Gen2"
)

const (
	OsState_Generalized OsState = "Generalized"
	OsState_Specialized OsState = "Specialized"
)

const (
	AdminEventTypes_BillingOwnerDeleted = "BillingOwnerDeleted"
)
