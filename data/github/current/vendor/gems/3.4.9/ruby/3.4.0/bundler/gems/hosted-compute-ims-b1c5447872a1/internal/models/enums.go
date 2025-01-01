package models

type (
	ImageVersionState string
	OsType            string
	ImageType         string
	Architecture      string
)

const (
	GithubOwnerId      = "github"
	LatestImageVersion = "latest"
)

const (
	ImageVersionState_Pending         ImageVersionState = "Pending"
	ImageVersionState_Provisioning    ImageVersionState = "Provisioning"
	ImageVersionState_Ready           ImageVersionState = "Ready"
	ImageVersionState_ProvisionFailed ImageVersionState = "ProvisionFailed"
	ImageVersionState_Deleting        ImageVersionState = "Deleting"
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
