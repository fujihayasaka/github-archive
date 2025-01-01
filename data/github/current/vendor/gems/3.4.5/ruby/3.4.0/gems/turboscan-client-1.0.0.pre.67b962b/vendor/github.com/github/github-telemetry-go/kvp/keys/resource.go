// DO NOT EDIT MANUALLY!!! Code generated from github/github-semantic-conventions/go/templates/keys.j2

// Deprecated: services should use the semantic conventions directly
// As of https://github.com/github/observability/pull/3479 this code will no
// longer be kept up to date with the latest conventions
package keys

// The web browser in which the application represented by the resource is running. The `browser.*`
// attributes MUST be used only for resources that represent applications running in a web browser
// (regardless of whether running on a mobile or desktop device).
type browser struct {
	// Brands is the string value of the browser.brands key
	//
	// Array of brand name and version separated by a space
	//
	// Type: string[]
	//
	// Examples:
	//   ' Not A;Brand 99', 'Chromium 99', 'Chrome 99'
	//
	// Note:
	// This value is intended to be taken from the UA client hints API
	// (navigator.userAgentData.brands).
	Brands string
	// Platform is the string value of the browser.platform key
	//
	// The platform on which the browser is running
	//
	// Type: string
	//
	// Examples:
	//   'Windows', 'macOS', 'Android'
	//
	// Note:
	// This value is intended to be taken from the UA client hints API
	// (navigator.userAgentData.platform). If unavailable, the legacy `navigator.platform` API SHOULD
	// NOT be used instead and this attribute SHOULD be left unset in order for the values to be
	// consistent. The list of possible values is defined in the W3C User-Agent Client Hints
	// specification. Note that some (but not all) of these values can overlap with values in the
	// os.type and os.name attributes. However, for consistency, the values in the `browser.platform`
	// attribute should capture the exact value that the user agent provides.
	Platform string
	// UserAgent is the string value of the browser.user_agent key
	//
	// Full user-agent string provided by the browser
	//
	// Type: string
	//
	// Examples:
	//   'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, '
	//  'like Gecko) Chrome/95.0.4638.54 Safari/537.36'
	//
	// Note:
	// The user-agent value SHOULD be provided only from browsers that do not have a mechanism to
	// retrieve brands and platform individually from the User-Agent Client Hints API. To retrieve
	// the value, the legacy `navigator.userAgent` API can be used.
	UserAgent string
}

// The web browser in which the application represented by the resource is running. The `browser.*`
// attributes MUST be used only for resources that represent applications running in a web browser
// (regardless of whether running on a mobile or desktop device).
var Browser = browser{
	Brands:    "browser.brands",
	Platform:  "browser.platform",
	UserAgent: "browser.user_agent",
}

// A cloud environment (e.g. GCP, Azure, AWS)
type cloud struct {
	// Provider is the string value of the cloud.provider key
	//
	// Name of the cloud provider.
	//
	// Type: Enum
	Provider string
	// AccountId is the string value of the cloud.account.id key
	//
	// The cloud account ID the resource is assigned to.
	//
	// Type: string
	//
	// Examples:
	//   '111111111111', 'opentelemetry'
	AccountId string
	// Region is the string value of the cloud.region key
	//
	// The geographical region the resource is running.
	//
	// Type: string
	//
	// Examples:
	//   'us-central1', 'us-east-1'
	//
	// Note:
	// Refer to your provider's docs to see the available regions, for example Alibaba Cloud regions,
	// AWS regions, Azure regions, Google Cloud regions, or Tencent Cloud regions.
	Region string
	// AvailabilityZone is the string value of the cloud.availability_zone key
	//
	// Cloud regions often have multiple, isolated locations known as zones to increase availability.
	// Availability zone represents the zone where the resource is running.
	//
	// Type: string
	//
	// Examples:
	//   'us-east-1c'
	//
	// Note:
	// Availability zones are called "zones" on Alibaba Cloud and Google Cloud.
	AvailabilityZone string
	// Platform is the string value of the cloud.platform key
	//
	// The cloud platform in use.
	//
	// Type: Enum
	//
	// Note:
	// The prefix of the service SHOULD match the one specified in `cloud.provider`.
	Platform string
}

// A cloud environment (e.g. GCP, Azure, AWS)
var Cloud = cloud{
	Provider:         "cloud.provider",
	AccountId:        "cloud.account.id",
	Region:           "cloud.region",
	AvailabilityZone: "cloud.availability_zone",
	Platform:         "cloud.platform",
}

// Resources used by AWS Elastic Container Service (ECS).
type awsEcs struct {
	// ContainerArn is the string value of the aws.ecs.container.arn key
	//
	// The Amazon Resource Name (ARN) of an [ECS container
	// instance](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ECS_instances.html).
	//
	// Type: string
	//
	// Examples:
	//   'arn:aws:ecs:us-west-1:123456789123:container/32624152-9086-4f0e-acae-1a75b14fe4d9'
	ContainerArn string
	// ClusterArn is the string value of the aws.ecs.cluster.arn key
	//
	// The ARN of an [ECS
	// cluster](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/clusters.html).
	//
	// Type: string
	//
	// Examples:
	//   'arn:aws:ecs:us-west-2:123456789123:cluster/my-cluster'
	ClusterArn string
	// Launchtype is the string value of the aws.ecs.launchtype key
	//
	// The [launch type](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/launch_types.html)
	// for an ECS task.
	//
	// Type: Enum
	Launchtype string
	// TaskArn is the string value of the aws.ecs.task.arn key
	//
	// The ARN of an [ECS task
	// definition](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html).
	//
	// Type: string
	//
	// Examples:
	//   'arn:aws:ecs:us-west-1:123456789123:task/10838bed-421f-43ef-870a-f43feacbbb5b'
	TaskArn string
	// TaskFamily is the string value of the aws.ecs.task.family key
	//
	// The task definition family this task definition is a member of.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry-family'
	TaskFamily string
	// TaskRevision is the string value of the aws.ecs.task.revision key
	//
	// The revision for this task definition.
	//
	// Type: string
	//
	// Examples:
	//   '8', '26'
	TaskRevision string
}

// Resources used by AWS Elastic Container Service (ECS).
var AwsEcs = awsEcs{
	ContainerArn: "aws.ecs.container.arn",
	ClusterArn:   "aws.ecs.cluster.arn",
	Launchtype:   "aws.ecs.launchtype",
	TaskArn:      "aws.ecs.task.arn",
	TaskFamily:   "aws.ecs.task.family",
	TaskRevision: "aws.ecs.task.revision",
}

// Resources used by AWS Elastic Kubernetes Service (EKS).
type awsEks struct {
	// ClusterArn is the string value of the aws.eks.cluster.arn key
	//
	// The ARN of an EKS cluster.
	//
	// Type: string
	//
	// Examples:
	//   'arn:aws:ecs:us-west-2:123456789123:cluster/my-cluster'
	ClusterArn string
}

// Resources used by AWS Elastic Kubernetes Service (EKS).
var AwsEks = awsEks{
	ClusterArn: "aws.eks.cluster.arn",
}

// Resources specific to Amazon Web Services.
type awsLog struct {
	// GroupNames is the string value of the aws.log.group.names key
	//
	// The name(s) of the AWS log group(s) an application is writing to.
	//
	// Type: string[]
	//
	// Examples:
	//   '/aws/lambda/my-function', 'opentelemetry-service'
	//
	// Note:
	// Multiple log groups must be supported for cases like multi-container applications, where a
	// single application has sidecar containers, and each write to their own log group.
	GroupNames string
	// GroupArns is the string value of the aws.log.group.arns key
	//
	// The Amazon Resource Name(s) (ARN) of the AWS log group(s).
	//
	// Type: string[]
	//
	// Examples:
	//   'arn:aws:logs:us-west-1:123456789012:log-group:/aws/my/group:*'
	//
	// Note:
	// See the log group ARN format documentation.
	GroupArns string
	// StreamNames is the string value of the aws.log.stream.names key
	//
	// The name(s) of the AWS log stream(s) an application is writing to.
	//
	// Type: string[]
	//
	// Examples:
	//   'logs/main/10838bed-421f-43ef-870a-f43feacbbb5b'
	StreamNames string
	// StreamArns is the string value of the aws.log.stream.arns key
	//
	// The ARN(s) of the AWS log stream(s).
	//
	// Type: string[]
	//
	// Examples:
	//   'arn:aws:logs:us-west-1:123456789012:log-group:/aws/my/group:log-
	// stream:logs/main/10838bed-421f-43ef-870a-f43feacbbb5b'
	//
	// Note:
	// See the log stream ARN format documentation. One log group can contain several log streams, so
	// these ARNs necessarily identify both a log group and a log stream.
	StreamArns string
}

// Resources specific to Amazon Web Services.
var AwsLog = awsLog{
	GroupNames:  "aws.log.group.names",
	GroupArns:   "aws.log.group.arns",
	StreamNames: "aws.log.stream.names",
	StreamArns:  "aws.log.stream.arns",
}

// A container instance.
type container struct {
	// Name is the string value of the container.name key
	//
	// Container name used by container runtime.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry-autoconf'
	Name string
	// Id is the string value of the container.id key
	//
	// Container ID. Usually a UUID, as for example used to [identify Docker
	// containers](https://docs.docker.com/engine/reference/run/#container-identification). The UUID
	// might be abbreviated.
	//
	// Type: string
	//
	// Examples:
	//   'a3bf90e006b2'
	Id string
	// Runtime is the string value of the container.runtime key
	//
	// The container runtime managing this container.
	//
	// Type: string
	//
	// Examples:
	//   'docker', 'containerd', 'rkt'
	Runtime string
	// ImageName is the string value of the container.image.name key
	//
	// Name of the image the container was built on.
	//
	// Type: string
	//
	// Examples:
	//   'gcr.io/opentelemetry/operator'
	ImageName string
	// ImageTag is the string value of the container.image.tag key
	//
	// Container image tag.
	//
	// Type: string
	//
	// Examples:
	//   '0.1'
	ImageTag string
}

// A container instance.
var Container = container{
	Name:      "container.name",
	Id:        "container.id",
	Runtime:   "container.runtime",
	ImageName: "container.image.name",
	ImageTag:  "container.image.tag",
}

// The software deployment.
type deployment struct {
	// Environment is the string value of the deployment.environment key
	//
	// Name of the [deployment environment](https://en.wikipedia.org/wiki/Deployment_environment) (aka
	// deployment tier).
	//
	// Type: string
	//
	// Examples:
	//   'staging', 'production'
	Environment string
}

// The software deployment.
var Deployment = deployment{
	Environment: "deployment.environment",
}

// The device on which the process represented by this resource is running.
type device struct {
	// Id is the string value of the device.id key
	//
	// A unique identifier representing the device
	//
	// Type: string
	//
	// Examples:
	//   '2ab2916d-a51f-4ac8-80ee-45ac31a28092'
	//
	// Note:
	// The device identifier MUST only be defined using the values outlined below. This value is not
	// an advertising identifier and MUST NOT be used as such. On iOS (Swift or Objective-C), this
	// value MUST be equal to the vendor identifier. On Android (Java or Kotlin), this value MUST be
	// equal to the Firebase Installation ID or a globally unique UUID which is persisted across
	// sessions in your application. More information can be found here on best practices and exact
	// implementation details. Caution should be taken when storing personal data or anything which
	// can identify a user. GDPR and data protection laws may apply, ensure you do your own due
	// diligence.
	Id string
	// ModelIdentifier is the string value of the device.model.identifier key
	//
	// The model identifier for the device
	//
	// Type: string
	//
	// Examples:
	//   'iPhone3,4', 'SM-G920F'
	//
	// Note:
	// It's recommended this value represents a machine readable version of the model identifier
	// rather than the market or consumer-friendly name of the device.
	ModelIdentifier string
	// ModelName is the string value of the device.model.name key
	//
	// The marketing name for the device model
	//
	// Type: string
	//
	// Examples:
	//   'iPhone 6s Plus', 'Samsung Galaxy S6'
	//
	// Note:
	// It's recommended this value represents a human readable version of the device model rather
	// than a machine readable alternative.
	ModelName string
	// Manufacturer is the string value of the device.manufacturer key
	//
	// The name of the device manufacturer
	//
	// Type: string
	//
	// Examples:
	//   'Apple', 'Samsung'
	//
	// Note:
	// The Android OS provides this field via Build. iOS apps SHOULD hardcode the value `Apple`.
	Manufacturer string
}

// The device on which the process represented by this resource is running.
var Device = device{
	Id:              "device.id",
	ModelIdentifier: "device.model.identifier",
	ModelName:       "device.model.name",
	Manufacturer:    "device.manufacturer",
}

// A serverless instance.
type faasResource struct {
	// Name is the string value of the faas.name key
	//
	// The name of the single function that this runtime instance executes.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'my-function', 'myazurefunctionapp/some-function-name'
	//
	// Note:
	// This is the name of the function as configured/deployed on the FaaS platform and is usually
	// different from the name of the callback function (which may be stored in the
	// `code.namespace`/`code.function` span attributes).
	//
	// For some cloud providers, the above definition is ambiguous. The following definition of
	// function name MUST be used for this attribute (and consequently the span name) for the listed
	// cloud providers/products:
	//
	// * Azure:  The full name `<FUNCAPP>/<FUNC>`, i.e., function app name
	//   followed by a forward slash followed by the function name (this form
	//   can also be seen in the resource JSON for the function).
	//   This means that a span attribute MUST be used, as an Azure function
	//   app can host multiple functions that would usually share
	//   a TracerProvider (see also the `faas.id` attribute).
	Name string
	// Id is the string value of the faas.id key
	//
	// The unique ID of the single function that this runtime instance executes.
	//
	// Type: string
	//
	// Examples:
	//   'arn:aws:lambda:us-west-2:123456789012:function:my-function'
	//
	// Note:
	// On some cloud providers, it may not be possible to determine the full ID at startup, so
	// consider setting `faas.id` as a span attribute instead.
	//
	// The exact value to use for `faas.id` depends on the cloud provider:
	//
	// * AWS Lambda: The function ARN.
	//   Take care not to use the "invoked ARN" directly but replace any
	//   alias suffix
	//   with the resolved function version, as the same runtime instance may be invokable with
	//   multiple different aliases.
	// * GCP: The URI of the resource
	// * Azure: The Fully Qualified Resource ID of the invoked function,
	//   *not* the function app, having the form
	//   `/subscriptions/<SUBSCIPTION_GUID>/resourceGroups/<RG>/providers/Microsoft.Web/sites/<FUNCAP
	// P>/functions/<FUNC>`.
	//   This means that a span attribute MUST be used, as an Azure function app can host multiple
	// functions that would usually share
	//   a TracerProvider.
	Id string
	// Version is the string value of the faas.version key
	//
	// The immutable version of the function being executed.
	//
	// Type: string
	//
	// Examples:
	//   '26', 'pinkfroid-00002'
	//
	// Note:
	// Depending on the cloud provider and platform, use:
	//
	// * AWS Lambda: The function version
	//   (an integer represented as a decimal string).
	// * Google Cloud Run: The revision
	//   (i.e., the function name plus the revision suffix).
	// * Google Cloud Functions: The value of the
	//   `K_REVISION` environment variable.
	// * Azure Functions: Not applicable. Do not set this attribute.
	Version string
	// Instance is the string value of the faas.instance key
	//
	// The execution environment ID as a string, that will be potentially reused for other invocations
	// to the same function/function version.
	//
	// Type: string
	//
	// Examples:
	//   '2021/06/28/[$LATEST]2f399eb14537447da05ab2a2e39309de'
	//
	// Note:
	// - AWS Lambda: Use the (full) log stream name.
	Instance string
	// MaxMemory is the string value of the faas.max_memory key
	//
	// The amount of memory available to the serverless function in MiB.
	//
	// Type: int
	//
	// Examples:
	//   128
	//
	// Note:
	// It's recommended to set this attribute since e.g. too little memory can easily stop a Java AWS
	// Lambda function from working correctly. On AWS Lambda, the environment variable
	// `AWS_LAMBDA_FUNCTION_MEMORY_SIZE` provides this information.
	MaxMemory string
}

// A serverless instance.
var FaasResource = faasResource{
	Name:      "faas.name",
	Id:        "faas.id",
	Version:   "faas.version",
	Instance:  "faas.instance",
	MaxMemory: "faas.max_memory",
}

// Attributes specific to a particular software release.
type ghRelease struct {
	// GitRef is the string value of the gh.release.git.ref key
	//
	// Git [reference](https://git-scm.com/book/en/v2/Git-Internals-Git-References) for the current
	// deployment
	//
	// Type: string
	//
	// Examples:
	//   'main', 'master', 'my-test-branch'
	GitRef string
}

// Attributes specific to a particular software release.
var GhRelease = ghRelease{
	GitRef: "gh.release.git.ref",
}

// Attributes specific to an artifact for deployment
type ghArtifact struct {
	// Fingerprint is the string value of the gh.artifact.fingerprint key
	//
	// Unique identifier for the build artifact
	//
	// Type: string
	//
	// Examples:
	//   'ad567f8c38884e4456a14cdb4f216f7ff287115e', 'BUILD-123', '20220225.183914'
	//
	// Note:
	// Possible values would include a hash of the generated binary, a build number, or a build
	// timestamp
	Fingerprint string
}

// Attributes specific to an artifact for deployment
var GhArtifact = ghArtifact{
	Fingerprint: "gh.artifact.fingerprint",
}

// This group is used to define the semantic conventions for infrastructure related data.
type ghInfra struct {
	// Site is the string value of the gh.infra.site key
	//
	// Short name for a site/datacenter.  List of current sites can be found in [sites-
	// api](https://github.com/github/sites-api/blob/master/config/sites.yml).
	//
	// Type: string
	//
	// Examples:
	//   'ash1-iad', 'ac4-iad', 'azure-eastus'
	Site string
	// Rack is the string value of the gh.infra.rack key
	//
	// Rack identifier for where the server is located in the datacenter.
	//
	// Type: string
	//
	// Examples:
	//   'm6', 'bw115'
	Rack string
	// App is the string value of the gh.infra.app key
	//
	// Used by puppet to identify the application/service a given host is related to.
	//
	// Type: string
	//
	// Examples:
	//   'github', 'glb', 'heaven'
	App string
	// Role is the string value of the gh.infra.role key
	//
	// Used by puppet to identify the role inside a service a given host is related to.
	//
	// Type: string
	//
	// Examples:
	//   'memcached', 'db', 'web'
	Role string
	// AppRole is the string value of the gh.infra.app_role key
	//
	// The app and role puppet related attributes contatenated together and separated with a dash.
	//
	// Type: string
	//
	// Examples:
	//   'github-lowworker', 'db-mysql', 'heaven-fe'
	AppRole string
	// HostSerial is the string value of the gh.infra.host.serial key
	//
	// Serial number of the host.
	//
	// Type: string
	//
	// Examples:
	//   '78MEG34', 'ec2af397-8326-d34f-d8fa-0ca38339d91'
	HostSerial string
	// HostParentChassis is the string value of the gh.infra.host.parent_chassis key
	//
	// Serial number of the parent chassis, if applicable.
	//
	// Type: string
	//
	// Examples:
	//   '78KH227'
	HostParentChassis string
	// OsRelease is the string value of the gh.infra.os.release key
	//
	// Name of operating system release.  On linux this should be the output of `lsb_release -c -s`.
	//
	// Type: string
	//
	// Examples:
	//   'jessie', 'stretch'
	OsRelease string
}

// This group is used to define the semantic conventions for infrastructure related data.
var GhInfra = ghInfra{
	Site:              "gh.infra.site",
	Rack:              "gh.infra.rack",
	App:               "gh.infra.app",
	Role:              "gh.infra.role",
	AppRole:           "gh.infra.app_role",
	HostSerial:        "gh.infra.host.serial",
	HostParentChassis: "gh.infra.host.parent_chassis",
	OsRelease:         "gh.infra.os.release",
}

// Attributes specific to GitHubs OpenTelemetry SDK's.
type ghSdk struct {
	// Name is the string value of the gh.sdk.name key
	//
	// The name of the GitHub OpenTelemetry SDK being used.
	//
	// Type: string
	//
	// Examples:
	//   'github-telemetry-go'
	//
	// Note:
	// This is the name of the language specific SDK being used for OpenTelemetry implementations.
	// This will typically be named after the GitHub repository storing the SDK code. For example,
	// the GitHub Go OpenTelemetry SDK is named "github-telemetry-go" because the repo for the code
	// exist in http://github.com/github/github-telemetry-go.
	Name string
	// Version is the string value of the gh.sdk.version key
	//
	// The version of the GitHub OpenTelemetry SDK being used.
	//
	// Type: string
	//
	// Examples:
	//   '1.0.0', '2.0.0', '3.0.0'
	//
	// Note:
	// This is the version assigned to the language specific SDK being used that is represented by
	// `gh.sdk.name`. The version should be a semantic version with major, minor, and patch versions.
	Version string
}

// Attributes specific to GitHubs OpenTelemetry SDK's.
var GhSdk = ghSdk{
	Name:    "gh.sdk.name",
	Version: "gh.sdk.version",
}

// A host is defined as a general computing instance.
type host struct {
	// Id is the string value of the host.id key
	//
	// Unique host ID. For Cloud, this must be the instance_id assigned by the cloud provider.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry-test'
	Id string
	// Name is the string value of the host.name key
	//
	// Name of the host. On Unix systems, it may contain what the hostname command returns, or the fully
	// qualified hostname, or another name specified by the user.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry-test'
	Name string
	// Type is the string value of the host.type key
	//
	// Type of host. For Cloud, this must be the machine type.
	//
	// Type: string
	//
	// Examples:
	//   'n1-standard-1'
	Type string
	// Arch is the string value of the host.arch key
	//
	// The CPU architecture the host system is running on.
	//
	// Type: Enum
	Arch string
	// ImageName is the string value of the host.image.name key
	//
	// Name of the VM image or OS install the host was instantiated from.
	//
	// Type: string
	//
	// Examples:
	//   'infra-ami-eks-worker-node-7d4ec78312', 'CentOS-8-x86_64-1905'
	ImageName string
	// ImageId is the string value of the host.image.id key
	//
	// VM image ID. For Cloud, this value is from the provider.
	//
	// Type: string
	//
	// Examples:
	//   'ami-07b06b442921831e5'
	ImageId string
	// ImageVersion is the string value of the host.image.version key
	//
	// The version string of the VM image as defined in [Version Attributes](README.md#version-
	// attributes).
	//
	// Type: string
	//
	// Examples:
	//   '0.1'
	ImageVersion string
}

// A host is defined as a general computing instance.
var Host = host{
	Id:           "host.id",
	Name:         "host.name",
	Type:         "host.type",
	Arch:         "host.arch",
	ImageName:    "host.image.name",
	ImageId:      "host.image.id",
	ImageVersion: "host.image.version",
}

// A Kubernetes Cluster.
type k8sCluster struct {
	// Name is the string value of the k8s.cluster.name key
	//
	// The name of the cluster.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry-cluster'
	Name string
}

// A Kubernetes Cluster.
var K8sCluster = k8sCluster{
	Name: "k8s.cluster.name",
}

// A Kubernetes Node object.
type k8sNode struct {
	// Name is the string value of the k8s.node.name key
	//
	// The name of the Node.
	//
	// Type: string
	//
	// Examples:
	//   'node-1'
	Name string
	// Uid is the string value of the k8s.node.uid key
	//
	// The UID of the Node.
	//
	// Type: string
	//
	// Examples:
	//   '1eb3a0c6-0477-4080-a9cb-0cb7db65c6a2'
	Uid string
}

// A Kubernetes Node object.
var K8sNode = k8sNode{
	Name: "k8s.node.name",
	Uid:  "k8s.node.uid",
}

// A Kubernetes Namespace.
type k8sNamespace struct {
	// Name is the string value of the k8s.namespace.name key
	//
	// The name of the namespace that the pod is running in.
	//
	// Type: string
	//
	// Examples:
	//   'default'
	Name string
}

// A Kubernetes Namespace.
var K8sNamespace = k8sNamespace{
	Name: "k8s.namespace.name",
}

// A Kubernetes Pod object.
type k8sPod struct {
	// Uid is the string value of the k8s.pod.uid key
	//
	// The UID of the Pod.
	//
	// Type: string
	//
	// Examples:
	//   '275ecb36-5aa8-4c2a-9c47-d8bb681b9aff'
	Uid string
	// Name is the string value of the k8s.pod.name key
	//
	// The name of the Pod.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry-pod-autoconf'
	Name string
}

// A Kubernetes Pod object.
var K8sPod = k8sPod{
	Uid:  "k8s.pod.uid",
	Name: "k8s.pod.name",
}

// A container in a [PodTemplate](https://kubernetes.io/docs/concepts/workloads/pods/#pod-
// templates).
type k8sContainer struct {
	// Name is the string value of the k8s.container.name key
	//
	// The name of the Container from Pod specification, must be unique within a Pod. Container runtime
	// usually uses different globally unique name (`container.name`).
	//
	// Type: string
	//
	// Examples:
	//   'redis'
	Name string
	// RestartCount is the string value of the k8s.container.restart_count key
	//
	// Number of times the container was restarted. This attribute can be used to identify a particular
	// container (running or stopped) within a container spec.
	//
	// Type: int
	//
	// Examples:
	//   0, 2
	RestartCount string
}

// A container in a [PodTemplate](https://kubernetes.io/docs/concepts/workloads/pods/#pod-
// templates).
var K8sContainer = k8sContainer{
	Name:         "k8s.container.name",
	RestartCount: "k8s.container.restart_count",
}

// A Kubernetes ReplicaSet object.
type k8sReplicaset struct {
	// Uid is the string value of the k8s.replicaset.uid key
	//
	// The UID of the ReplicaSet.
	//
	// Type: string
	//
	// Examples:
	//   '275ecb36-5aa8-4c2a-9c47-d8bb681b9aff'
	Uid string
	// Name is the string value of the k8s.replicaset.name key
	//
	// The name of the ReplicaSet.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry'
	Name string
}

// A Kubernetes ReplicaSet object.
var K8sReplicaset = k8sReplicaset{
	Uid:  "k8s.replicaset.uid",
	Name: "k8s.replicaset.name",
}

// A Kubernetes Deployment object.
type k8sDeployment struct {
	// Uid is the string value of the k8s.deployment.uid key
	//
	// The UID of the Deployment.
	//
	// Type: string
	//
	// Examples:
	//   '275ecb36-5aa8-4c2a-9c47-d8bb681b9aff'
	Uid string
	// Name is the string value of the k8s.deployment.name key
	//
	// The name of the Deployment.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry'
	Name string
}

// A Kubernetes Deployment object.
var K8sDeployment = k8sDeployment{
	Uid:  "k8s.deployment.uid",
	Name: "k8s.deployment.name",
}

// A Kubernetes StatefulSet object.
type k8sStatefulset struct {
	// Uid is the string value of the k8s.statefulset.uid key
	//
	// The UID of the StatefulSet.
	//
	// Type: string
	//
	// Examples:
	//   '275ecb36-5aa8-4c2a-9c47-d8bb681b9aff'
	Uid string
	// Name is the string value of the k8s.statefulset.name key
	//
	// The name of the StatefulSet.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry'
	Name string
}

// A Kubernetes StatefulSet object.
var K8sStatefulset = k8sStatefulset{
	Uid:  "k8s.statefulset.uid",
	Name: "k8s.statefulset.name",
}

// A Kubernetes DaemonSet object.
type k8sDaemonset struct {
	// Uid is the string value of the k8s.daemonset.uid key
	//
	// The UID of the DaemonSet.
	//
	// Type: string
	//
	// Examples:
	//   '275ecb36-5aa8-4c2a-9c47-d8bb681b9aff'
	Uid string
	// Name is the string value of the k8s.daemonset.name key
	//
	// The name of the DaemonSet.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry'
	Name string
}

// A Kubernetes DaemonSet object.
var K8sDaemonset = k8sDaemonset{
	Uid:  "k8s.daemonset.uid",
	Name: "k8s.daemonset.name",
}

// A Kubernetes Job object.
type k8sJob struct {
	// Uid is the string value of the k8s.job.uid key
	//
	// The UID of the Job.
	//
	// Type: string
	//
	// Examples:
	//   '275ecb36-5aa8-4c2a-9c47-d8bb681b9aff'
	Uid string
	// Name is the string value of the k8s.job.name key
	//
	// The name of the Job.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry'
	Name string
}

// A Kubernetes Job object.
var K8sJob = k8sJob{
	Uid:  "k8s.job.uid",
	Name: "k8s.job.name",
}

// A Kubernetes CronJob object.
type k8sCronjob struct {
	// Uid is the string value of the k8s.cronjob.uid key
	//
	// The UID of the CronJob.
	//
	// Type: string
	//
	// Examples:
	//   '275ecb36-5aa8-4c2a-9c47-d8bb681b9aff'
	Uid string
	// Name is the string value of the k8s.cronjob.name key
	//
	// The name of the CronJob.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry'
	Name string
}

// A Kubernetes CronJob object.
var K8sCronjob = k8sCronjob{
	Uid:  "k8s.cronjob.uid",
	Name: "k8s.cronjob.name",
}

// The operating system (OS) on which the process represented by this resource is running.
type os struct {
	// Type is the string value of the os.type key
	//
	// The operating system type.
	//
	// Type: Enum
	//
	// Requirement Level: Required
	Type string
	// Description is the string value of the os.description key
	//
	// Human readable (not intended to be parsed) OS version information, like e.g. reported by `ver` or
	// `lsb_release -a` commands.
	//
	// Type: string
	//
	// Examples:
	//   'Microsoft Windows [Version 10.0.18363.778]', 'Ubuntu 18.04.1 LTS'
	Description string
	// Name is the string value of the os.name key
	//
	// Human readable operating system name.
	//
	// Type: string
	//
	// Examples:
	//   'iOS', 'Android', 'Ubuntu'
	Name string
	// Version is the string value of the os.version key
	//
	// The version string of the operating system as defined in [Version
	// Attributes](../../resource/semantic_conventions/README.md#version-attributes).
	//
	// Type: string
	//
	// Examples:
	//   '14.2.1', '18.04.1'
	Version string
}

// The operating system (OS) on which the process represented by this resource is running.
var Os = os{
	Type:        "os.type",
	Description: "os.description",
	Name:        "os.name",
	Version:     "os.version",
}

// An operating system process.
type process struct {
	// Pid is the string value of the process.pid key
	//
	// Process identifier (PID).
	//
	// Type: int
	//
	// Examples:
	//   1234
	Pid string
	// ParentPid is the string value of the process.parent_pid key
	//
	// Parent Process identifier (PID).
	//
	// Type: int
	//
	// Examples:
	//   111
	ParentPid string
	// ExecutableName is the string value of the process.executable.name key
	//
	// The name of the process executable. On Linux based systems, can be set to the `Name` in
	// `proc/[pid]/status`. On Windows, can be set to the base name of `GetProcessImageFileNameW`.
	//
	// Type: string
	//
	// Requirement Level: Conditionally Required - See alternative attributes below.
	//
	// Examples:
	//   'otelcol'
	ExecutableName string
	// ExecutablePath is the string value of the process.executable.path key
	//
	// The full path to the process executable. On Linux based systems, can be set to the target of
	// `proc/[pid]/exe`. On Windows, can be set to the result of `GetProcessImageFileNameW`.
	//
	// Type: string
	//
	// Requirement Level: Conditionally Required - See alternative attributes below.
	//
	// Examples:
	//   '/usr/bin/cmd/otelcol'
	ExecutablePath string
	// Command is the string value of the process.command key
	//
	// The command used to launch the process (i.e. the command name). On Linux based systems, can be
	// set to the zeroth string in `proc/[pid]/cmdline`. On Windows, can be set to the first parameter
	// extracted from `GetCommandLineW`.
	//
	// Type: string
	//
	// Requirement Level: Conditionally Required - See alternative attributes below.
	//
	// Examples:
	//   'cmd/otelcol'
	Command string
	// CommandLine is the string value of the process.command_line key
	//
	// The full command used to launch the process as a single string representing the full command. On
	// Windows, can be set to the result of `GetCommandLineW`. Do not set this if you have to assemble
	// it just for monitoring; use `process.command_args` instead.
	//
	// Type: string
	//
	// Requirement Level: Conditionally Required - See alternative attributes below.
	//
	// Examples:
	//   'C:\\cmd\\otecol --config="my directory\\config.yaml"'
	CommandLine string
	// CommandArgs is the string value of the process.command_args key
	//
	// All the command arguments (including the command/executable itself) as received by the process.
	// On Linux-based systems (and some other Unixoid systems supporting procfs), can be set according
	// to the list of null-delimited strings extracted from `proc/[pid]/cmdline`. For libc-based
	// executables, this would be the full argv vector passed to `main`.
	//
	// Type: string[]
	//
	// Requirement Level: Conditionally Required - See alternative attributes below.
	//
	// Examples:
	//   'cmd/otecol', '--config=config.yaml'
	CommandArgs string
	// Owner is the string value of the process.owner key
	//
	// The username of the user that owns the process.
	//
	// Type: string
	//
	// Examples:
	//   'root'
	Owner string
}

// An operating system process.
var Process = process{
	Pid:            "process.pid",
	ParentPid:      "process.parent_pid",
	ExecutableName: "process.executable.name",
	ExecutablePath: "process.executable.path",
	Command:        "process.command",
	CommandLine:    "process.command_line",
	CommandArgs:    "process.command_args",
	Owner:          "process.owner",
}

// The single (language) runtime instance which is monitored.
type processRuntime struct {
	// Name is the string value of the process.runtime.name key
	//
	// The name of the runtime of this process. For compiled native binaries, this SHOULD be the name of
	// the compiler.
	//
	// Type: string
	//
	// Examples:
	//   'OpenJDK Runtime Environment'
	Name string
	// Version is the string value of the process.runtime.version key
	//
	// The version of the runtime of this process, as returned by the runtime without modification.
	//
	// Type: string
	//
	// Examples:
	//   '14.0.2'
	Version string
	// Description is the string value of the process.runtime.description key
	//
	// An additional description about the runtime of the process, for example a specific vendor
	// customization of the runtime environment.
	//
	// Type: string
	//
	// Examples:
	//   'Eclipse OpenJ9 Eclipse OpenJ9 VM openj9-0.21.0'
	Description string
}

// The single (language) runtime instance which is monitored.
var ProcessRuntime = processRuntime{
	Name:        "process.runtime.name",
	Version:     "process.runtime.version",
	Description: "process.runtime.description",
}

// A service instance.
type service struct {
	// Name is the string value of the service.name key
	//
	// Logical name of the service.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'shoppingcart'
	//
	// Note:
	// MUST be the same for all instances of horizontally scaled services. If the value was not
	// specified, SDKs MUST fallback to `unknown_service:` concatenated with
	// `process.executable.name`, e.g. `unknown_service:bash`. If `process.executable.name` is not
	// available, the value MUST be set to `unknown_service`.
	Name string
	// Namespace is the string value of the service.namespace key
	//
	// A namespace for `service.name`.
	//
	// Type: string
	//
	// Examples:
	//   'Shop'
	//
	// Note:
	// A string value having a meaning that helps to distinguish a group of services, for example the
	// team name that owns a group of services. `service.name` is expected to be unique within the
	// same namespace. If `service.namespace` is not specified in the Resource then `service.name` is
	// expected to be unique for all services that have no explicit namespace defined (so the
	// empty/unspecified namespace is simply one more valid namespace). Zero-length namespace string
	// is assumed equal to unspecified namespace.
	Namespace string
	// InstanceId is the string value of the service.instance.id key
	//
	// The string ID of the service instance.
	//
	// Type: string
	//
	// Examples:
	//   '627cc493-f310-47de-96bd-71410b7dec09'
	//
	// Note:
	// MUST be unique for each instance of the same `service.namespace,service.name` pair (in other
	// words `service.namespace,service.name,service.instance.id` triplet MUST be globally unique).
	// The ID helps to distinguish instances of the same service that exist at the same time (e.g.
	// instances of a horizontally scaled service). It is preferable for the ID to be persistent and
	// stay the same for the lifetime of the service instance, however it is acceptable that the ID
	// is ephemeral and changes during important lifetime events for the service (e.g. service
	// restarts). If the service has no inherent unique ID that can be used as the value of this
	// attribute it is recommended to generate a random Version 1 or Version 4 RFC 4122 UUID
	// (services aiming for reproducible UUIDs may also use Version 5, see RFC 4122 for more
	// recommendations).
	InstanceId string
	// Version is the string value of the service.version key
	//
	// The version string of the service API or implementation.
	//
	// Type: string
	//
	// Examples:
	//   '2.0.0'
	Version string
}

// A service instance.
var Service = service{
	Name:       "service.name",
	Namespace:  "service.namespace",
	InstanceId: "service.instance.id",
	Version:    "service.version",
}

// The telemetry SDK used to capture data recorded by the instrumentation libraries.
type telemetry struct {
	// SdkName is the string value of the telemetry.sdk.name key
	//
	// The name of the telemetry SDK as defined above.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry'
	SdkName string
	// SdkLanguage is the string value of the telemetry.sdk.language key
	//
	// The language of the telemetry SDK.
	//
	// Type: Enum
	SdkLanguage string
	// SdkVersion is the string value of the telemetry.sdk.version key
	//
	// The version string of the telemetry SDK.
	//
	// Type: string
	//
	// Examples:
	//   '1.2.3'
	SdkVersion string
	// AutoVersion is the string value of the telemetry.auto.version key
	//
	// The version string of the auto instrumentation agent, if used.
	//
	// Type: string
	//
	// Examples:
	//   '1.2.3'
	AutoVersion string
}

// The telemetry SDK used to capture data recorded by the instrumentation libraries.
var Telemetry = telemetry{
	SdkName:     "telemetry.sdk.name",
	SdkLanguage: "telemetry.sdk.language",
	SdkVersion:  "telemetry.sdk.version",
	AutoVersion: "telemetry.auto.version",
}

// Resource describing the packaged software running the application code. Web engines are typically
// executed using process.runtime.
type webengineResource struct {
	// Name is the string value of the webengine.name key
	//
	// The name of the web engine.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'WildFly'
	Name string
	// Version is the string value of the webengine.version key
	//
	// The version of the web engine.
	//
	// Type: string
	//
	// Examples:
	//   '21.0.0'
	Version string
	// Description is the string value of the webengine.description key
	//
	// Additional description of the web engine (e.g. detailed version and edition information).
	//
	// Type: string
	//
	// Examples:
	//   'WildFly Full 21.0.0.Final (WildFly Core 13.0.1.Final) - 2.2.2.Final'
	Description string
}

// Resource describing the packaged software running the application code. Web engines are typically
// executed using process.runtime.
var WebengineResource = webengineResource{
	Name:        "webengine.name",
	Version:     "webengine.version",
	Description: "webengine.description",
}
