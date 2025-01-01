// DO NOT EDIT MANUALLY!!! This is generated code from:
// Repo:     github/github-semantic-conventions
// Script:   script/update-go
// Template: go/templates/fields.j2

// Deprecated: services should use the semantic conventions directly
// As of https://github.com/github/observability/pull/3479 this code will no
// longer be kept up to date with the latest conventions
package fields

import (
	"github.com/github/github-telemetry-go/kvp"
)

// The web browser in which the application represented by the resource is running. The `browser.*`
// attributes MUST be used only for resources that represent applications running in a web browser
// (regardless of whether running on a mobile or desktop device).
type browser struct {
	// Brands returns a kvp.Field with the browser.brands key and the value you provide.
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
	Brands func(value ...string) kvp.Field

	// Platform returns a kvp.Field with the browser.platform key and the value you provide.
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
	Platform func(value string) kvp.Field

	// UserAgent returns a kvp.Field with the browser.user_agent key and the value you provide.
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
	UserAgent func(value string) kvp.Field
}

// The web browser in which the application represented by the resource is running. The `browser.*`
// attributes MUST be used only for resources that represent applications running in a web browser
// (regardless of whether running on a mobile or desktop device).
var Browser = browser{
	Brands: func(value ...string) kvp.Field {
		return kvp.Strings("browser.brands", value)
	},

	Platform: func(value string) kvp.Field {
		return kvp.String("browser.platform", value)
	},

	UserAgent: func(value string) kvp.Field {
		return kvp.String("browser.user_agent", value)
	},
}

// A cloud environment (e.g. GCP, Azure, AWS)
type cloud struct {

	// Provider struct
	//
	// Name of the cloud provider.
	//
	// Type: Enum
	Provider struct {
		// AlibabaCloud is a kvp.Field with key "cloud.provider" and value "alibaba_cloud"
		//
		// Alibaba Cloud
		AlibabaCloud kvp.Field

		// Aws is a kvp.Field with key "cloud.provider" and value "aws"
		//
		// Amazon Web Services
		Aws kvp.Field

		// Azure is a kvp.Field with key "cloud.provider" and value "azure"
		//
		// Microsoft Azure
		Azure kvp.Field

		// Gcp is a kvp.Field with key "cloud.provider" and value "gcp"
		//
		// Google Cloud Platform
		Gcp kvp.Field

		// TencentCloud is a kvp.Field with key "cloud.provider" and value "tencent_cloud"
		//
		// Tencent Cloud
		TencentCloud kvp.Field

		// CustomValue returns a kvp.Field with key "cloud.provider" and the value you pass in.
		CustomValue func(value string) kvp.Field
	}

	// AccountId returns a kvp.Field with the cloud.account.id key and the value you provide.
	//
	// The cloud account ID the resource is assigned to.
	//
	// Type: string
	//
	// Examples:
	//   '111111111111', 'opentelemetry'
	AccountId func(value string) kvp.Field

	// Region returns a kvp.Field with the cloud.region key and the value you provide.
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
	Region func(value string) kvp.Field

	// AvailabilityZone returns a kvp.Field with the cloud.availability_zone key and the value you provide.
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
	AvailabilityZone func(value string) kvp.Field

	// Platform struct
	//
	// The cloud platform in use.
	//
	// Type: Enum
	//
	// Note:
	// The prefix of the service SHOULD match the one specified in `cloud.provider`.
	Platform struct {
		// AlibabaCloudEcs is a kvp.Field with key "cloud.platform" and value "alibaba_cloud_ecs"
		//
		// Alibaba Cloud Elastic Compute Service
		AlibabaCloudEcs kvp.Field

		// AlibabaCloudFc is a kvp.Field with key "cloud.platform" and value "alibaba_cloud_fc"
		//
		// Alibaba Cloud Function Compute
		AlibabaCloudFc kvp.Field

		// AwsEc2 is a kvp.Field with key "cloud.platform" and value "aws_ec2"
		//
		// AWS Elastic Compute Cloud
		AwsEc2 kvp.Field

		// AwsEcs is a kvp.Field with key "cloud.platform" and value "aws_ecs"
		//
		// AWS Elastic Container Service
		AwsEcs kvp.Field

		// AwsEks is a kvp.Field with key "cloud.platform" and value "aws_eks"
		//
		// AWS Elastic Kubernetes Service
		AwsEks kvp.Field

		// AwsLambda is a kvp.Field with key "cloud.platform" and value "aws_lambda"
		//
		// AWS Lambda
		AwsLambda kvp.Field

		// AwsElasticBeanstalk is a kvp.Field with key "cloud.platform" and value "aws_elastic_beanstalk"
		//
		// AWS Elastic Beanstalk
		AwsElasticBeanstalk kvp.Field

		// AwsAppRunner is a kvp.Field with key "cloud.platform" and value "aws_app_runner"
		//
		// AWS App Runner
		AwsAppRunner kvp.Field

		// AzureVm is a kvp.Field with key "cloud.platform" and value "azure_vm"
		//
		// Azure Virtual Machines
		AzureVm kvp.Field

		// AzureContainerInstances is a kvp.Field with key "cloud.platform" and value "azure_container_instances"
		//
		// Azure Container Instances
		AzureContainerInstances kvp.Field

		// AzureAks is a kvp.Field with key "cloud.platform" and value "azure_aks"
		//
		// Azure Kubernetes Service
		AzureAks kvp.Field

		// AzureFunctions is a kvp.Field with key "cloud.platform" and value "azure_functions"
		//
		// Azure Functions
		AzureFunctions kvp.Field

		// AzureAppService is a kvp.Field with key "cloud.platform" and value "azure_app_service"
		//
		// Azure App Service
		AzureAppService kvp.Field

		// GcpComputeEngine is a kvp.Field with key "cloud.platform" and value "gcp_compute_engine"
		//
		// Google Cloud Compute Engine (GCE)
		GcpComputeEngine kvp.Field

		// GcpCloudRun is a kvp.Field with key "cloud.platform" and value "gcp_cloud_run"
		//
		// Google Cloud Run
		GcpCloudRun kvp.Field

		// GcpKubernetesEngine is a kvp.Field with key "cloud.platform" and value "gcp_kubernetes_engine"
		//
		// Google Cloud Kubernetes Engine (GKE)
		GcpKubernetesEngine kvp.Field

		// GcpCloudFunctions is a kvp.Field with key "cloud.platform" and value "gcp_cloud_functions"
		//
		// Google Cloud Functions (GCF)
		GcpCloudFunctions kvp.Field

		// GcpAppEngine is a kvp.Field with key "cloud.platform" and value "gcp_app_engine"
		//
		// Google Cloud App Engine (GAE)
		GcpAppEngine kvp.Field

		// TencentCloudCvm is a kvp.Field with key "cloud.platform" and value "tencent_cloud_cvm"
		//
		// Tencent Cloud Cloud Virtual Machine (CVM)
		TencentCloudCvm kvp.Field

		// TencentCloudEks is a kvp.Field with key "cloud.platform" and value "tencent_cloud_eks"
		//
		// Tencent Cloud Elastic Kubernetes Service (EKS)
		TencentCloudEks kvp.Field

		// TencentCloudScf is a kvp.Field with key "cloud.platform" and value "tencent_cloud_scf"
		//
		// Tencent Cloud Serverless Cloud Function (SCF)
		TencentCloudScf kvp.Field

		// CustomValue returns a kvp.Field with key "cloud.platform" and the value you pass in.
		CustomValue func(value string) kvp.Field
	}
}

// A cloud environment (e.g. GCP, Azure, AWS)
var Cloud = cloud{
	Provider: struct {
		AlibabaCloud kvp.Field
		Aws          kvp.Field
		Azure        kvp.Field
		Gcp          kvp.Field
		TencentCloud kvp.Field
		CustomValue  func(value string) kvp.Field
	}{
		AlibabaCloud: kvp.String("cloud.provider", "alibaba_cloud"),
		Aws:          kvp.String("cloud.provider", "aws"),
		Azure:        kvp.String("cloud.provider", "azure"),
		Gcp:          kvp.String("cloud.provider", "gcp"),
		TencentCloud: kvp.String("cloud.provider", "tencent_cloud"),
		CustomValue: func(value string) kvp.Field {
			return kvp.String("cloud.provider", value)
		},
	},

	AccountId: func(value string) kvp.Field {
		return kvp.String("cloud.account.id", value)
	},

	Region: func(value string) kvp.Field {
		return kvp.String("cloud.region", value)
	},

	AvailabilityZone: func(value string) kvp.Field {
		return kvp.String("cloud.availability_zone", value)
	},

	Platform: struct {
		AlibabaCloudEcs         kvp.Field
		AlibabaCloudFc          kvp.Field
		AwsEc2                  kvp.Field
		AwsEcs                  kvp.Field
		AwsEks                  kvp.Field
		AwsLambda               kvp.Field
		AwsElasticBeanstalk     kvp.Field
		AwsAppRunner            kvp.Field
		AzureVm                 kvp.Field
		AzureContainerInstances kvp.Field
		AzureAks                kvp.Field
		AzureFunctions          kvp.Field
		AzureAppService         kvp.Field
		GcpComputeEngine        kvp.Field
		GcpCloudRun             kvp.Field
		GcpKubernetesEngine     kvp.Field
		GcpCloudFunctions       kvp.Field
		GcpAppEngine            kvp.Field
		TencentCloudCvm         kvp.Field
		TencentCloudEks         kvp.Field
		TencentCloudScf         kvp.Field
		CustomValue             func(value string) kvp.Field
	}{
		AlibabaCloudEcs:         kvp.String("cloud.platform", "alibaba_cloud_ecs"),
		AlibabaCloudFc:          kvp.String("cloud.platform", "alibaba_cloud_fc"),
		AwsEc2:                  kvp.String("cloud.platform", "aws_ec2"),
		AwsEcs:                  kvp.String("cloud.platform", "aws_ecs"),
		AwsEks:                  kvp.String("cloud.platform", "aws_eks"),
		AwsLambda:               kvp.String("cloud.platform", "aws_lambda"),
		AwsElasticBeanstalk:     kvp.String("cloud.platform", "aws_elastic_beanstalk"),
		AwsAppRunner:            kvp.String("cloud.platform", "aws_app_runner"),
		AzureVm:                 kvp.String("cloud.platform", "azure_vm"),
		AzureContainerInstances: kvp.String("cloud.platform", "azure_container_instances"),
		AzureAks:                kvp.String("cloud.platform", "azure_aks"),
		AzureFunctions:          kvp.String("cloud.platform", "azure_functions"),
		AzureAppService:         kvp.String("cloud.platform", "azure_app_service"),
		GcpComputeEngine:        kvp.String("cloud.platform", "gcp_compute_engine"),
		GcpCloudRun:             kvp.String("cloud.platform", "gcp_cloud_run"),
		GcpKubernetesEngine:     kvp.String("cloud.platform", "gcp_kubernetes_engine"),
		GcpCloudFunctions:       kvp.String("cloud.platform", "gcp_cloud_functions"),
		GcpAppEngine:            kvp.String("cloud.platform", "gcp_app_engine"),
		TencentCloudCvm:         kvp.String("cloud.platform", "tencent_cloud_cvm"),
		TencentCloudEks:         kvp.String("cloud.platform", "tencent_cloud_eks"),
		TencentCloudScf:         kvp.String("cloud.platform", "tencent_cloud_scf"),
		CustomValue: func(value string) kvp.Field {
			return kvp.String("cloud.platform", value)
		},
	},
}

// Resources used by AWS Elastic Container Service (ECS).
type awsEcs struct {
	// ContainerArn returns a kvp.Field with the aws.ecs.container.arn key and the value you provide.
	//
	// The Amazon Resource Name (ARN) of an [ECS container
	// instance](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ECS_instances.html).
	//
	// Type: string
	//
	// Examples:
	//   'arn:aws:ecs:us-west-1:123456789123:container/32624152-9086-4f0e-acae-1a75b14fe4d9'
	ContainerArn func(value string) kvp.Field

	// ClusterArn returns a kvp.Field with the aws.ecs.cluster.arn key and the value you provide.
	//
	// The ARN of an [ECS
	// cluster](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/clusters.html).
	//
	// Type: string
	//
	// Examples:
	//   'arn:aws:ecs:us-west-2:123456789123:cluster/my-cluster'
	ClusterArn func(value string) kvp.Field

	// Launchtype struct
	//
	// The [launch type](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/launch_types.html)
	// for an ECS task.
	//
	// Type: Enum
	Launchtype struct {
		// Ec2 is a kvp.Field with key "aws.ecs.launchtype" and value "ec2"
		//
		// ec2
		Ec2 kvp.Field

		// Fargate is a kvp.Field with key "aws.ecs.launchtype" and value "fargate"
		//
		// fargate
		Fargate kvp.Field
	}

	// TaskArn returns a kvp.Field with the aws.ecs.task.arn key and the value you provide.
	//
	// The ARN of an [ECS task
	// definition](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html).
	//
	// Type: string
	//
	// Examples:
	//   'arn:aws:ecs:us-west-1:123456789123:task/10838bed-421f-43ef-870a-f43feacbbb5b'
	TaskArn func(value string) kvp.Field

	// TaskFamily returns a kvp.Field with the aws.ecs.task.family key and the value you provide.
	//
	// The task definition family this task definition is a member of.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry-family'
	TaskFamily func(value string) kvp.Field

	// TaskRevision returns a kvp.Field with the aws.ecs.task.revision key and the value you provide.
	//
	// The revision for this task definition.
	//
	// Type: string
	//
	// Examples:
	//   '8', '26'
	TaskRevision func(value string) kvp.Field
}

// Resources used by AWS Elastic Container Service (ECS).
var AwsEcs = awsEcs{
	ContainerArn: func(value string) kvp.Field {
		return kvp.String("aws.ecs.container.arn", value)
	},

	ClusterArn: func(value string) kvp.Field {
		return kvp.String("aws.ecs.cluster.arn", value)
	},

	Launchtype: struct {
		Ec2     kvp.Field
		Fargate kvp.Field
	}{
		Ec2:     kvp.String("aws.ecs.launchtype", "ec2"),
		Fargate: kvp.String("aws.ecs.launchtype", "fargate"),
	},

	TaskArn: func(value string) kvp.Field {
		return kvp.String("aws.ecs.task.arn", value)
	},

	TaskFamily: func(value string) kvp.Field {
		return kvp.String("aws.ecs.task.family", value)
	},

	TaskRevision: func(value string) kvp.Field {
		return kvp.String("aws.ecs.task.revision", value)
	},
}

// Resources used by AWS Elastic Kubernetes Service (EKS).
type awsEks struct {
	// ClusterArn returns a kvp.Field with the aws.eks.cluster.arn key and the value you provide.
	//
	// The ARN of an EKS cluster.
	//
	// Type: string
	//
	// Examples:
	//   'arn:aws:ecs:us-west-2:123456789123:cluster/my-cluster'
	ClusterArn func(value string) kvp.Field
}

// Resources used by AWS Elastic Kubernetes Service (EKS).
var AwsEks = awsEks{
	ClusterArn: func(value string) kvp.Field {
		return kvp.String("aws.eks.cluster.arn", value)
	},
}

// Resources specific to Amazon Web Services.
type awsLog struct {
	// GroupNames returns a kvp.Field with the aws.log.group.names key and the value you provide.
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
	GroupNames func(value ...string) kvp.Field

	// GroupArns returns a kvp.Field with the aws.log.group.arns key and the value you provide.
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
	GroupArns func(value ...string) kvp.Field

	// StreamNames returns a kvp.Field with the aws.log.stream.names key and the value you provide.
	//
	// The name(s) of the AWS log stream(s) an application is writing to.
	//
	// Type: string[]
	//
	// Examples:
	//   'logs/main/10838bed-421f-43ef-870a-f43feacbbb5b'
	StreamNames func(value ...string) kvp.Field

	// StreamArns returns a kvp.Field with the aws.log.stream.arns key and the value you provide.
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
	StreamArns func(value ...string) kvp.Field
}

// Resources specific to Amazon Web Services.
var AwsLog = awsLog{
	GroupNames: func(value ...string) kvp.Field {
		return kvp.Strings("aws.log.group.names", value)
	},

	GroupArns: func(value ...string) kvp.Field {
		return kvp.Strings("aws.log.group.arns", value)
	},

	StreamNames: func(value ...string) kvp.Field {
		return kvp.Strings("aws.log.stream.names", value)
	},

	StreamArns: func(value ...string) kvp.Field {
		return kvp.Strings("aws.log.stream.arns", value)
	},
}

// A container instance.
type container struct {
	// Name returns a kvp.Field with the container.name key and the value you provide.
	//
	// Container name used by container runtime.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry-autoconf'
	Name func(value string) kvp.Field

	// Id returns a kvp.Field with the container.id key and the value you provide.
	//
	// Container ID. Usually a UUID, as for example used to [identify Docker
	// containers](https://docs.docker.com/engine/reference/run/#container-identification). The UUID
	// might be abbreviated.
	//
	// Type: string
	//
	// Examples:
	//   'a3bf90e006b2'
	Id func(value string) kvp.Field

	// Runtime returns a kvp.Field with the container.runtime key and the value you provide.
	//
	// The container runtime managing this container.
	//
	// Type: string
	//
	// Examples:
	//   'docker', 'containerd', 'rkt'
	Runtime func(value string) kvp.Field

	// ImageName returns a kvp.Field with the container.image.name key and the value you provide.
	//
	// Name of the image the container was built on.
	//
	// Type: string
	//
	// Examples:
	//   'gcr.io/opentelemetry/operator'
	ImageName func(value string) kvp.Field

	// ImageTag returns a kvp.Field with the container.image.tag key and the value you provide.
	//
	// Container image tag.
	//
	// Type: string
	//
	// Examples:
	//   '0.1'
	ImageTag func(value string) kvp.Field
}

// A container instance.
var Container = container{
	Name: func(value string) kvp.Field {
		return kvp.String("container.name", value)
	},

	Id: func(value string) kvp.Field {
		return kvp.String("container.id", value)
	},

	Runtime: func(value string) kvp.Field {
		return kvp.String("container.runtime", value)
	},

	ImageName: func(value string) kvp.Field {
		return kvp.String("container.image.name", value)
	},

	ImageTag: func(value string) kvp.Field {
		return kvp.String("container.image.tag", value)
	},
}

// The software deployment.
type deployment struct {
	// Environment returns a kvp.Field with the deployment.environment key and the value you provide.
	//
	// Name of the [deployment environment](https://en.wikipedia.org/wiki/Deployment_environment) (aka
	// deployment tier).
	//
	// Type: string
	//
	// Examples:
	//   'staging', 'production'
	Environment func(value string) kvp.Field
}

// The software deployment.
var Deployment = deployment{
	Environment: func(value string) kvp.Field {
		return kvp.String("deployment.environment", value)
	},
}

// The device on which the process represented by this resource is running.
type device struct {
	// Id returns a kvp.Field with the device.id key and the value you provide.
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
	Id func(value string) kvp.Field

	// ModelIdentifier returns a kvp.Field with the device.model.identifier key and the value you provide.
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
	ModelIdentifier func(value string) kvp.Field

	// ModelName returns a kvp.Field with the device.model.name key and the value you provide.
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
	ModelName func(value string) kvp.Field

	// Manufacturer returns a kvp.Field with the device.manufacturer key and the value you provide.
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
	Manufacturer func(value string) kvp.Field
}

// The device on which the process represented by this resource is running.
var Device = device{
	Id: func(value string) kvp.Field {
		return kvp.String("device.id", value)
	},

	ModelIdentifier: func(value string) kvp.Field {
		return kvp.String("device.model.identifier", value)
	},

	ModelName: func(value string) kvp.Field {
		return kvp.String("device.model.name", value)
	},

	Manufacturer: func(value string) kvp.Field {
		return kvp.String("device.manufacturer", value)
	},
}

// A serverless instance.
type faasResource struct {
	// Name returns a kvp.Field with the faas.name key and the value you provide.
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
	Name func(value string) kvp.Field

	// Id returns a kvp.Field with the faas.id key and the value you provide.
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
	Id func(value string) kvp.Field

	// Version returns a kvp.Field with the faas.version key and the value you provide.
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
	Version func(value string) kvp.Field

	// Instance returns a kvp.Field with the faas.instance key and the value you provide.
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
	Instance func(value string) kvp.Field

	// MaxMemory returns a kvp.Field with the faas.max_memory key and the value you provide.
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
	MaxMemory func(value int) kvp.Field
}

// A serverless instance.
var FaasResource = faasResource{
	Name: func(value string) kvp.Field {
		return kvp.String("faas.name", value)
	},

	Id: func(value string) kvp.Field {
		return kvp.String("faas.id", value)
	},

	Version: func(value string) kvp.Field {
		return kvp.String("faas.version", value)
	},

	Instance: func(value string) kvp.Field {
		return kvp.String("faas.instance", value)
	},

	MaxMemory: func(value int) kvp.Field {
		return kvp.Int("faas.max_memory", value)
	},
}

// Attributes specific to a particular software release.
type ghRelease struct {
	// GitRef returns a kvp.Field with the gh.release.git.ref key and the value you provide.
	//
	// Git [reference](https://git-scm.com/book/en/v2/Git-Internals-Git-References) for the current
	// deployment
	//
	// Type: string
	//
	// Examples:
	//   'main', 'master', 'my-test-branch'
	GitRef func(value string) kvp.Field
}

// Attributes specific to a particular software release.
var GhRelease = ghRelease{
	GitRef: func(value string) kvp.Field {
		return kvp.String("gh.release.git.ref", value)
	},
}

// Attributes specific to an artifact for deployment
type ghArtifact struct {
	// Fingerprint returns a kvp.Field with the gh.artifact.fingerprint key and the value you provide.
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
	Fingerprint func(value string) kvp.Field
}

// Attributes specific to an artifact for deployment
var GhArtifact = ghArtifact{
	Fingerprint: func(value string) kvp.Field {
		return kvp.String("gh.artifact.fingerprint", value)
	},
}

// This group is used to define the semantic conventions for infrastructure related data.
type ghInfra struct {
	// Site returns a kvp.Field with the gh.infra.site key and the value you provide.
	//
	// Short name for a site/datacenter.  List of current sites can be found in [sites-
	// api](https://github.com/github/sites-api/blob/master/config/sites.yml).
	//
	// Type: string
	//
	// Examples:
	//   'ash1-iad', 'ac4-iad', 'azure-eastus'
	Site func(value string) kvp.Field

	// Rack returns a kvp.Field with the gh.infra.rack key and the value you provide.
	//
	// Rack identifier for where the server is located in the datacenter.
	//
	// Type: string
	//
	// Examples:
	//   'm6', 'bw115'
	Rack func(value string) kvp.Field

	// App returns a kvp.Field with the gh.infra.app key and the value you provide.
	//
	// Used by puppet to identify the application/service a given host is related to.
	//
	// Type: string
	//
	// Examples:
	//   'github', 'glb', 'heaven'
	App func(value string) kvp.Field

	// Role returns a kvp.Field with the gh.infra.role key and the value you provide.
	//
	// Used by puppet to identify the role inside a service a given host is related to.
	//
	// Type: string
	//
	// Examples:
	//   'memcached', 'db', 'web'
	Role func(value string) kvp.Field

	// AppRole returns a kvp.Field with the gh.infra.app_role key and the value you provide.
	//
	// The app and role puppet related attributes contatenated together and separated with a dash.
	//
	// Type: string
	//
	// Examples:
	//   'github-lowworker', 'db-mysql', 'heaven-fe'
	AppRole func(value string) kvp.Field

	// HostSerial returns a kvp.Field with the gh.infra.host.serial key and the value you provide.
	//
	// Serial number of the host.
	//
	// Type: string
	//
	// Examples:
	//   '78MEG34', 'ec2af397-8326-d34f-d8fa-0ca38339d91'
	HostSerial func(value string) kvp.Field

	// HostParentChassis returns a kvp.Field with the gh.infra.host.parent_chassis key and the value you provide.
	//
	// Serial number of the parent chassis, if applicable.
	//
	// Type: string
	//
	// Examples:
	//   '78KH227'
	HostParentChassis func(value string) kvp.Field

	// OsRelease returns a kvp.Field with the gh.infra.os.release key and the value you provide.
	//
	// Name of operating system release.  On linux this should be the output of `lsb_release -c -s`.
	//
	// Type: string
	//
	// Examples:
	//   'jessie', 'stretch'
	OsRelease func(value string) kvp.Field
}

// This group is used to define the semantic conventions for infrastructure related data.
var GhInfra = ghInfra{
	Site: func(value string) kvp.Field {
		return kvp.String("gh.infra.site", value)
	},

	Rack: func(value string) kvp.Field {
		return kvp.String("gh.infra.rack", value)
	},

	App: func(value string) kvp.Field {
		return kvp.String("gh.infra.app", value)
	},

	Role: func(value string) kvp.Field {
		return kvp.String("gh.infra.role", value)
	},

	AppRole: func(value string) kvp.Field {
		return kvp.String("gh.infra.app_role", value)
	},

	HostSerial: func(value string) kvp.Field {
		return kvp.String("gh.infra.host.serial", value)
	},

	HostParentChassis: func(value string) kvp.Field {
		return kvp.String("gh.infra.host.parent_chassis", value)
	},

	OsRelease: func(value string) kvp.Field {
		return kvp.String("gh.infra.os.release", value)
	},
}

// Attributes specific to GitHubs OpenTelemetry SDK's.
type ghSdk struct {
	// Name returns a kvp.Field with the gh.sdk.name key and the value you provide.
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
	Name func(value string) kvp.Field

	// Version returns a kvp.Field with the gh.sdk.version key and the value you provide.
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
	Version func(value string) kvp.Field
}

// Attributes specific to GitHubs OpenTelemetry SDK's.
var GhSdk = ghSdk{
	Name: func(value string) kvp.Field {
		return kvp.String("gh.sdk.name", value)
	},

	Version: func(value string) kvp.Field {
		return kvp.String("gh.sdk.version", value)
	},
}

// A host is defined as a general computing instance.
type host struct {
	// Id returns a kvp.Field with the host.id key and the value you provide.
	//
	// Unique host ID. For Cloud, this must be the instance_id assigned by the cloud provider.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry-test'
	Id func(value string) kvp.Field

	// Name returns a kvp.Field with the host.name key and the value you provide.
	//
	// Name of the host. On Unix systems, it may contain what the hostname command returns, or the fully
	// qualified hostname, or another name specified by the user.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry-test'
	Name func(value string) kvp.Field

	// Type returns a kvp.Field with the host.type key and the value you provide.
	//
	// Type of host. For Cloud, this must be the machine type.
	//
	// Type: string
	//
	// Examples:
	//   'n1-standard-1'
	Type func(value string) kvp.Field

	// Arch struct
	//
	// The CPU architecture the host system is running on.
	//
	// Type: Enum
	Arch struct {
		// Amd64 is a kvp.Field with key "host.arch" and value "amd64"
		//
		// AMD64
		Amd64 kvp.Field

		// Arm32 is a kvp.Field with key "host.arch" and value "arm32"
		//
		// ARM32
		Arm32 kvp.Field

		// Arm64 is a kvp.Field with key "host.arch" and value "arm64"
		//
		// ARM64
		Arm64 kvp.Field

		// Ia64 is a kvp.Field with key "host.arch" and value "ia64"
		//
		// Itanium
		Ia64 kvp.Field

		// Ppc32 is a kvp.Field with key "host.arch" and value "ppc32"
		//
		// 32-bit PowerPC
		Ppc32 kvp.Field

		// Ppc64 is a kvp.Field with key "host.arch" and value "ppc64"
		//
		// 64-bit PowerPC
		Ppc64 kvp.Field

		// S390x is a kvp.Field with key "host.arch" and value "s390x"
		//
		// IBM z/Architecture
		S390x kvp.Field

		// X86 is a kvp.Field with key "host.arch" and value "x86"
		//
		// 32-bit x86
		X86 kvp.Field

		// CustomValue returns a kvp.Field with key "host.arch" and the value you pass in.
		CustomValue func(value string) kvp.Field
	}

	// ImageName returns a kvp.Field with the host.image.name key and the value you provide.
	//
	// Name of the VM image or OS install the host was instantiated from.
	//
	// Type: string
	//
	// Examples:
	//   'infra-ami-eks-worker-node-7d4ec78312', 'CentOS-8-x86_64-1905'
	ImageName func(value string) kvp.Field

	// ImageId returns a kvp.Field with the host.image.id key and the value you provide.
	//
	// VM image ID. For Cloud, this value is from the provider.
	//
	// Type: string
	//
	// Examples:
	//   'ami-07b06b442921831e5'
	ImageId func(value string) kvp.Field

	// ImageVersion returns a kvp.Field with the host.image.version key and the value you provide.
	//
	// The version string of the VM image as defined in [Version Attributes](README.md#version-
	// attributes).
	//
	// Type: string
	//
	// Examples:
	//   '0.1'
	ImageVersion func(value string) kvp.Field
}

// A host is defined as a general computing instance.
var Host = host{
	Id: func(value string) kvp.Field {
		return kvp.String("host.id", value)
	},

	Name: func(value string) kvp.Field {
		return kvp.String("host.name", value)
	},

	Type: func(value string) kvp.Field {
		return kvp.String("host.type", value)
	},

	Arch: struct {
		Amd64       kvp.Field
		Arm32       kvp.Field
		Arm64       kvp.Field
		Ia64        kvp.Field
		Ppc32       kvp.Field
		Ppc64       kvp.Field
		S390x       kvp.Field
		X86         kvp.Field
		CustomValue func(value string) kvp.Field
	}{
		Amd64: kvp.String("host.arch", "amd64"),
		Arm32: kvp.String("host.arch", "arm32"),
		Arm64: kvp.String("host.arch", "arm64"),
		Ia64:  kvp.String("host.arch", "ia64"),
		Ppc32: kvp.String("host.arch", "ppc32"),
		Ppc64: kvp.String("host.arch", "ppc64"),
		S390x: kvp.String("host.arch", "s390x"),
		X86:   kvp.String("host.arch", "x86"),
		CustomValue: func(value string) kvp.Field {
			return kvp.String("host.arch", value)
		},
	},

	ImageName: func(value string) kvp.Field {
		return kvp.String("host.image.name", value)
	},

	ImageId: func(value string) kvp.Field {
		return kvp.String("host.image.id", value)
	},

	ImageVersion: func(value string) kvp.Field {
		return kvp.String("host.image.version", value)
	},
}

// A Kubernetes Cluster.
type k8sCluster struct {
	// Name returns a kvp.Field with the k8s.cluster.name key and the value you provide.
	//
	// The name of the cluster.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry-cluster'
	Name func(value string) kvp.Field
}

// A Kubernetes Cluster.
var K8sCluster = k8sCluster{
	Name: func(value string) kvp.Field {
		return kvp.String("k8s.cluster.name", value)
	},
}

// A Kubernetes Node object.
type k8sNode struct {
	// Name returns a kvp.Field with the k8s.node.name key and the value you provide.
	//
	// The name of the Node.
	//
	// Type: string
	//
	// Examples:
	//   'node-1'
	Name func(value string) kvp.Field

	// Uid returns a kvp.Field with the k8s.node.uid key and the value you provide.
	//
	// The UID of the Node.
	//
	// Type: string
	//
	// Examples:
	//   '1eb3a0c6-0477-4080-a9cb-0cb7db65c6a2'
	Uid func(value string) kvp.Field
}

// A Kubernetes Node object.
var K8sNode = k8sNode{
	Name: func(value string) kvp.Field {
		return kvp.String("k8s.node.name", value)
	},

	Uid: func(value string) kvp.Field {
		return kvp.String("k8s.node.uid", value)
	},
}

// A Kubernetes Namespace.
type k8sNamespace struct {
	// Name returns a kvp.Field with the k8s.namespace.name key and the value you provide.
	//
	// The name of the namespace that the pod is running in.
	//
	// Type: string
	//
	// Examples:
	//   'default'
	Name func(value string) kvp.Field
}

// A Kubernetes Namespace.
var K8sNamespace = k8sNamespace{
	Name: func(value string) kvp.Field {
		return kvp.String("k8s.namespace.name", value)
	},
}

// A Kubernetes Pod object.
type k8sPod struct {
	// Uid returns a kvp.Field with the k8s.pod.uid key and the value you provide.
	//
	// The UID of the Pod.
	//
	// Type: string
	//
	// Examples:
	//   '275ecb36-5aa8-4c2a-9c47-d8bb681b9aff'
	Uid func(value string) kvp.Field

	// Name returns a kvp.Field with the k8s.pod.name key and the value you provide.
	//
	// The name of the Pod.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry-pod-autoconf'
	Name func(value string) kvp.Field
}

// A Kubernetes Pod object.
var K8sPod = k8sPod{
	Uid: func(value string) kvp.Field {
		return kvp.String("k8s.pod.uid", value)
	},

	Name: func(value string) kvp.Field {
		return kvp.String("k8s.pod.name", value)
	},
}

// A container in a [PodTemplate](https://kubernetes.io/docs/concepts/workloads/pods/#pod-
// templates).
type k8sContainer struct {
	// Name returns a kvp.Field with the k8s.container.name key and the value you provide.
	//
	// The name of the Container from Pod specification, must be unique within a Pod. Container runtime
	// usually uses different globally unique name (`container.name`).
	//
	// Type: string
	//
	// Examples:
	//   'redis'
	Name func(value string) kvp.Field

	// RestartCount returns a kvp.Field with the k8s.container.restart_count key and the value you provide.
	//
	// Number of times the container was restarted. This attribute can be used to identify a particular
	// container (running or stopped) within a container spec.
	//
	// Type: int
	//
	// Examples:
	//   0, 2
	RestartCount func(value int) kvp.Field
}

// A container in a [PodTemplate](https://kubernetes.io/docs/concepts/workloads/pods/#pod-
// templates).
var K8sContainer = k8sContainer{
	Name: func(value string) kvp.Field {
		return kvp.String("k8s.container.name", value)
	},

	RestartCount: func(value int) kvp.Field {
		return kvp.Int("k8s.container.restart_count", value)
	},
}

// A Kubernetes ReplicaSet object.
type k8sReplicaset struct {
	// Uid returns a kvp.Field with the k8s.replicaset.uid key and the value you provide.
	//
	// The UID of the ReplicaSet.
	//
	// Type: string
	//
	// Examples:
	//   '275ecb36-5aa8-4c2a-9c47-d8bb681b9aff'
	Uid func(value string) kvp.Field

	// Name returns a kvp.Field with the k8s.replicaset.name key and the value you provide.
	//
	// The name of the ReplicaSet.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry'
	Name func(value string) kvp.Field
}

// A Kubernetes ReplicaSet object.
var K8sReplicaset = k8sReplicaset{
	Uid: func(value string) kvp.Field {
		return kvp.String("k8s.replicaset.uid", value)
	},

	Name: func(value string) kvp.Field {
		return kvp.String("k8s.replicaset.name", value)
	},
}

// A Kubernetes Deployment object.
type k8sDeployment struct {
	// Uid returns a kvp.Field with the k8s.deployment.uid key and the value you provide.
	//
	// The UID of the Deployment.
	//
	// Type: string
	//
	// Examples:
	//   '275ecb36-5aa8-4c2a-9c47-d8bb681b9aff'
	Uid func(value string) kvp.Field

	// Name returns a kvp.Field with the k8s.deployment.name key and the value you provide.
	//
	// The name of the Deployment.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry'
	Name func(value string) kvp.Field
}

// A Kubernetes Deployment object.
var K8sDeployment = k8sDeployment{
	Uid: func(value string) kvp.Field {
		return kvp.String("k8s.deployment.uid", value)
	},

	Name: func(value string) kvp.Field {
		return kvp.String("k8s.deployment.name", value)
	},
}

// A Kubernetes StatefulSet object.
type k8sStatefulset struct {
	// Uid returns a kvp.Field with the k8s.statefulset.uid key and the value you provide.
	//
	// The UID of the StatefulSet.
	//
	// Type: string
	//
	// Examples:
	//   '275ecb36-5aa8-4c2a-9c47-d8bb681b9aff'
	Uid func(value string) kvp.Field

	// Name returns a kvp.Field with the k8s.statefulset.name key and the value you provide.
	//
	// The name of the StatefulSet.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry'
	Name func(value string) kvp.Field
}

// A Kubernetes StatefulSet object.
var K8sStatefulset = k8sStatefulset{
	Uid: func(value string) kvp.Field {
		return kvp.String("k8s.statefulset.uid", value)
	},

	Name: func(value string) kvp.Field {
		return kvp.String("k8s.statefulset.name", value)
	},
}

// A Kubernetes DaemonSet object.
type k8sDaemonset struct {
	// Uid returns a kvp.Field with the k8s.daemonset.uid key and the value you provide.
	//
	// The UID of the DaemonSet.
	//
	// Type: string
	//
	// Examples:
	//   '275ecb36-5aa8-4c2a-9c47-d8bb681b9aff'
	Uid func(value string) kvp.Field

	// Name returns a kvp.Field with the k8s.daemonset.name key and the value you provide.
	//
	// The name of the DaemonSet.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry'
	Name func(value string) kvp.Field
}

// A Kubernetes DaemonSet object.
var K8sDaemonset = k8sDaemonset{
	Uid: func(value string) kvp.Field {
		return kvp.String("k8s.daemonset.uid", value)
	},

	Name: func(value string) kvp.Field {
		return kvp.String("k8s.daemonset.name", value)
	},
}

// A Kubernetes Job object.
type k8sJob struct {
	// Uid returns a kvp.Field with the k8s.job.uid key and the value you provide.
	//
	// The UID of the Job.
	//
	// Type: string
	//
	// Examples:
	//   '275ecb36-5aa8-4c2a-9c47-d8bb681b9aff'
	Uid func(value string) kvp.Field

	// Name returns a kvp.Field with the k8s.job.name key and the value you provide.
	//
	// The name of the Job.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry'
	Name func(value string) kvp.Field
}

// A Kubernetes Job object.
var K8sJob = k8sJob{
	Uid: func(value string) kvp.Field {
		return kvp.String("k8s.job.uid", value)
	},

	Name: func(value string) kvp.Field {
		return kvp.String("k8s.job.name", value)
	},
}

// A Kubernetes CronJob object.
type k8sCronjob struct {
	// Uid returns a kvp.Field with the k8s.cronjob.uid key and the value you provide.
	//
	// The UID of the CronJob.
	//
	// Type: string
	//
	// Examples:
	//   '275ecb36-5aa8-4c2a-9c47-d8bb681b9aff'
	Uid func(value string) kvp.Field

	// Name returns a kvp.Field with the k8s.cronjob.name key and the value you provide.
	//
	// The name of the CronJob.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry'
	Name func(value string) kvp.Field
}

// A Kubernetes CronJob object.
var K8sCronjob = k8sCronjob{
	Uid: func(value string) kvp.Field {
		return kvp.String("k8s.cronjob.uid", value)
	},

	Name: func(value string) kvp.Field {
		return kvp.String("k8s.cronjob.name", value)
	},
}

// The operating system (OS) on which the process represented by this resource is running.
type os struct {

	// Type struct
	//
	// The operating system type.
	//
	// Type: Enum
	//
	// Requirement Level: Required
	Type struct {
		// Windows is a kvp.Field with key "os.type" and value "windows"
		//
		// Microsoft Windows
		Windows kvp.Field

		// Linux is a kvp.Field with key "os.type" and value "linux"
		//
		// Linux
		Linux kvp.Field

		// Darwin is a kvp.Field with key "os.type" and value "darwin"
		//
		// Apple Darwin
		Darwin kvp.Field

		// Freebsd is a kvp.Field with key "os.type" and value "freebsd"
		//
		// FreeBSD
		Freebsd kvp.Field

		// Netbsd is a kvp.Field with key "os.type" and value "netbsd"
		//
		// NetBSD
		Netbsd kvp.Field

		// Openbsd is a kvp.Field with key "os.type" and value "openbsd"
		//
		// OpenBSD
		Openbsd kvp.Field

		// Dragonflybsd is a kvp.Field with key "os.type" and value "dragonflybsd"
		//
		// DragonFly BSD
		Dragonflybsd kvp.Field

		// Hpux is a kvp.Field with key "os.type" and value "hpux"
		//
		// HP-UX (Hewlett Packard Unix)
		Hpux kvp.Field

		// Aix is a kvp.Field with key "os.type" and value "aix"
		//
		// AIX (Advanced Interactive eXecutive)
		Aix kvp.Field

		// Solaris is a kvp.Field with key "os.type" and value "solaris"
		//
		// SunOS, Oracle Solaris
		Solaris kvp.Field

		// ZOs is a kvp.Field with key "os.type" and value "z_os"
		//
		// IBM z/OS
		ZOs kvp.Field

		// CustomValue returns a kvp.Field with key "os.type" and the value you pass in.
		CustomValue func(value string) kvp.Field
	}

	// Description returns a kvp.Field with the os.description key and the value you provide.
	//
	// Human readable (not intended to be parsed) OS version information, like e.g. reported by `ver` or
	// `lsb_release -a` commands.
	//
	// Type: string
	//
	// Examples:
	//   'Microsoft Windows [Version 10.0.18363.778]', 'Ubuntu 18.04.1 LTS'
	Description func(value string) kvp.Field

	// Name returns a kvp.Field with the os.name key and the value you provide.
	//
	// Human readable operating system name.
	//
	// Type: string
	//
	// Examples:
	//   'iOS', 'Android', 'Ubuntu'
	Name func(value string) kvp.Field

	// Version returns a kvp.Field with the os.version key and the value you provide.
	//
	// The version string of the operating system as defined in [Version
	// Attributes](../../resource/semantic_conventions/README.md#version-attributes).
	//
	// Type: string
	//
	// Examples:
	//   '14.2.1', '18.04.1'
	Version func(value string) kvp.Field
}

// The operating system (OS) on which the process represented by this resource is running.
var Os = os{
	Type: struct {
		Windows      kvp.Field
		Linux        kvp.Field
		Darwin       kvp.Field
		Freebsd      kvp.Field
		Netbsd       kvp.Field
		Openbsd      kvp.Field
		Dragonflybsd kvp.Field
		Hpux         kvp.Field
		Aix          kvp.Field
		Solaris      kvp.Field
		ZOs          kvp.Field
		CustomValue  func(value string) kvp.Field
	}{
		Windows:      kvp.String("os.type", "windows"),
		Linux:        kvp.String("os.type", "linux"),
		Darwin:       kvp.String("os.type", "darwin"),
		Freebsd:      kvp.String("os.type", "freebsd"),
		Netbsd:       kvp.String("os.type", "netbsd"),
		Openbsd:      kvp.String("os.type", "openbsd"),
		Dragonflybsd: kvp.String("os.type", "dragonflybsd"),
		Hpux:         kvp.String("os.type", "hpux"),
		Aix:          kvp.String("os.type", "aix"),
		Solaris:      kvp.String("os.type", "solaris"),
		ZOs:          kvp.String("os.type", "z_os"),
		CustomValue: func(value string) kvp.Field {
			return kvp.String("os.type", value)
		},
	},

	Description: func(value string) kvp.Field {
		return kvp.String("os.description", value)
	},

	Name: func(value string) kvp.Field {
		return kvp.String("os.name", value)
	},

	Version: func(value string) kvp.Field {
		return kvp.String("os.version", value)
	},
}

// An operating system process.
type process struct {
	// Pid returns a kvp.Field with the process.pid key and the value you provide.
	//
	// Process identifier (PID).
	//
	// Type: int
	//
	// Examples:
	//   1234
	Pid func(value int) kvp.Field

	// ParentPid returns a kvp.Field with the process.parent_pid key and the value you provide.
	//
	// Parent Process identifier (PID).
	//
	// Type: int
	//
	// Examples:
	//   111
	ParentPid func(value int) kvp.Field

	// ExecutableName returns a kvp.Field with the process.executable.name key and the value you provide.
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
	ExecutableName func(value string) kvp.Field

	// ExecutablePath returns a kvp.Field with the process.executable.path key and the value you provide.
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
	ExecutablePath func(value string) kvp.Field

	// Command returns a kvp.Field with the process.command key and the value you provide.
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
	Command func(value string) kvp.Field

	// CommandLine returns a kvp.Field with the process.command_line key and the value you provide.
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
	CommandLine func(value string) kvp.Field

	// CommandArgs returns a kvp.Field with the process.command_args key and the value you provide.
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
	CommandArgs func(value ...string) kvp.Field

	// Owner returns a kvp.Field with the process.owner key and the value you provide.
	//
	// The username of the user that owns the process.
	//
	// Type: string
	//
	// Examples:
	//   'root'
	Owner func(value string) kvp.Field
}

// An operating system process.
var Process = process{
	Pid: func(value int) kvp.Field {
		return kvp.Int("process.pid", value)
	},

	ParentPid: func(value int) kvp.Field {
		return kvp.Int("process.parent_pid", value)
	},

	ExecutableName: func(value string) kvp.Field {
		return kvp.String("process.executable.name", value)
	},

	ExecutablePath: func(value string) kvp.Field {
		return kvp.String("process.executable.path", value)
	},

	Command: func(value string) kvp.Field {
		return kvp.String("process.command", value)
	},

	CommandLine: func(value string) kvp.Field {
		return kvp.String("process.command_line", value)
	},

	CommandArgs: func(value ...string) kvp.Field {
		return kvp.Strings("process.command_args", value)
	},

	Owner: func(value string) kvp.Field {
		return kvp.String("process.owner", value)
	},
}

// The single (language) runtime instance which is monitored.
type processRuntime struct {
	// Name returns a kvp.Field with the process.runtime.name key and the value you provide.
	//
	// The name of the runtime of this process. For compiled native binaries, this SHOULD be the name of
	// the compiler.
	//
	// Type: string
	//
	// Examples:
	//   'OpenJDK Runtime Environment'
	Name func(value string) kvp.Field

	// Version returns a kvp.Field with the process.runtime.version key and the value you provide.
	//
	// The version of the runtime of this process, as returned by the runtime without modification.
	//
	// Type: string
	//
	// Examples:
	//   '14.0.2'
	Version func(value string) kvp.Field

	// Description returns a kvp.Field with the process.runtime.description key and the value you provide.
	//
	// An additional description about the runtime of the process, for example a specific vendor
	// customization of the runtime environment.
	//
	// Type: string
	//
	// Examples:
	//   'Eclipse OpenJ9 Eclipse OpenJ9 VM openj9-0.21.0'
	Description func(value string) kvp.Field
}

// The single (language) runtime instance which is monitored.
var ProcessRuntime = processRuntime{
	Name: func(value string) kvp.Field {
		return kvp.String("process.runtime.name", value)
	},

	Version: func(value string) kvp.Field {
		return kvp.String("process.runtime.version", value)
	},

	Description: func(value string) kvp.Field {
		return kvp.String("process.runtime.description", value)
	},
}

// A service instance.
type service struct {
	// Name returns a kvp.Field with the service.name key and the value you provide.
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
	Name func(value string) kvp.Field

	// Namespace returns a kvp.Field with the service.namespace key and the value you provide.
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
	Namespace func(value string) kvp.Field

	// InstanceId returns a kvp.Field with the service.instance.id key and the value you provide.
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
	InstanceId func(value string) kvp.Field

	// Version returns a kvp.Field with the service.version key and the value you provide.
	//
	// The version string of the service API or implementation.
	//
	// Type: string
	//
	// Examples:
	//   '2.0.0'
	Version func(value string) kvp.Field
}

// A service instance.
var Service = service{
	Name: func(value string) kvp.Field {
		return kvp.String("service.name", value)
	},

	Namespace: func(value string) kvp.Field {
		return kvp.String("service.namespace", value)
	},

	InstanceId: func(value string) kvp.Field {
		return kvp.String("service.instance.id", value)
	},

	Version: func(value string) kvp.Field {
		return kvp.String("service.version", value)
	},
}

// The telemetry SDK used to capture data recorded by the instrumentation libraries.
type telemetry struct {
	// SdkName returns a kvp.Field with the telemetry.sdk.name key and the value you provide.
	//
	// The name of the telemetry SDK as defined above.
	//
	// Type: string
	//
	// Examples:
	//   'opentelemetry'
	SdkName func(value string) kvp.Field

	// SdkLanguage struct
	//
	// The language of the telemetry SDK.
	//
	// Type: Enum
	SdkLanguage struct {
		// Cpp is a kvp.Field with key "telemetry.sdk.language" and value "cpp"
		//
		// cpp
		Cpp kvp.Field

		// Dotnet is a kvp.Field with key "telemetry.sdk.language" and value "dotnet"
		//
		// dotnet
		Dotnet kvp.Field

		// Erlang is a kvp.Field with key "telemetry.sdk.language" and value "erlang"
		//
		// erlang
		Erlang kvp.Field

		// Go is a kvp.Field with key "telemetry.sdk.language" and value "go"
		//
		// go
		Go kvp.Field

		// Java is a kvp.Field with key "telemetry.sdk.language" and value "java"
		//
		// java
		Java kvp.Field

		// Nodejs is a kvp.Field with key "telemetry.sdk.language" and value "nodejs"
		//
		// nodejs
		Nodejs kvp.Field

		// Php is a kvp.Field with key "telemetry.sdk.language" and value "php"
		//
		// php
		Php kvp.Field

		// Python is a kvp.Field with key "telemetry.sdk.language" and value "python"
		//
		// python
		Python kvp.Field

		// Ruby is a kvp.Field with key "telemetry.sdk.language" and value "ruby"
		//
		// ruby
		Ruby kvp.Field

		// Webjs is a kvp.Field with key "telemetry.sdk.language" and value "webjs"
		//
		// webjs
		Webjs kvp.Field

		// Swift is a kvp.Field with key "telemetry.sdk.language" and value "swift"
		//
		// swift
		Swift kvp.Field

		// CustomValue returns a kvp.Field with key "telemetry.sdk.language" and the value you pass in.
		CustomValue func(value string) kvp.Field
	}

	// SdkVersion returns a kvp.Field with the telemetry.sdk.version key and the value you provide.
	//
	// The version string of the telemetry SDK.
	//
	// Type: string
	//
	// Examples:
	//   '1.2.3'
	SdkVersion func(value string) kvp.Field

	// AutoVersion returns a kvp.Field with the telemetry.auto.version key and the value you provide.
	//
	// The version string of the auto instrumentation agent, if used.
	//
	// Type: string
	//
	// Examples:
	//   '1.2.3'
	AutoVersion func(value string) kvp.Field
}

// The telemetry SDK used to capture data recorded by the instrumentation libraries.
var Telemetry = telemetry{
	SdkName: func(value string) kvp.Field {
		return kvp.String("telemetry.sdk.name", value)
	},

	SdkLanguage: struct {
		Cpp         kvp.Field
		Dotnet      kvp.Field
		Erlang      kvp.Field
		Go          kvp.Field
		Java        kvp.Field
		Nodejs      kvp.Field
		Php         kvp.Field
		Python      kvp.Field
		Ruby        kvp.Field
		Webjs       kvp.Field
		Swift       kvp.Field
		CustomValue func(value string) kvp.Field
	}{
		Cpp:    kvp.String("telemetry.sdk.language", "cpp"),
		Dotnet: kvp.String("telemetry.sdk.language", "dotnet"),
		Erlang: kvp.String("telemetry.sdk.language", "erlang"),
		Go:     kvp.String("telemetry.sdk.language", "go"),
		Java:   kvp.String("telemetry.sdk.language", "java"),
		Nodejs: kvp.String("telemetry.sdk.language", "nodejs"),
		Php:    kvp.String("telemetry.sdk.language", "php"),
		Python: kvp.String("telemetry.sdk.language", "python"),
		Ruby:   kvp.String("telemetry.sdk.language", "ruby"),
		Webjs:  kvp.String("telemetry.sdk.language", "webjs"),
		Swift:  kvp.String("telemetry.sdk.language", "swift"),
		CustomValue: func(value string) kvp.Field {
			return kvp.String("telemetry.sdk.language", value)
		},
	},

	SdkVersion: func(value string) kvp.Field {
		return kvp.String("telemetry.sdk.version", value)
	},

	AutoVersion: func(value string) kvp.Field {
		return kvp.String("telemetry.auto.version", value)
	},
}

// Resource describing the packaged software running the application code. Web engines are typically
// executed using process.runtime.
type webengineResource struct {
	// Name returns a kvp.Field with the webengine.name key and the value you provide.
	//
	// The name of the web engine.
	//
	// Type: string
	//
	// Requirement Level: Required
	//
	// Examples:
	//   'WildFly'
	Name func(value string) kvp.Field

	// Version returns a kvp.Field with the webengine.version key and the value you provide.
	//
	// The version of the web engine.
	//
	// Type: string
	//
	// Examples:
	//   '21.0.0'
	Version func(value string) kvp.Field

	// Description returns a kvp.Field with the webengine.description key and the value you provide.
	//
	// Additional description of the web engine (e.g. detailed version and edition information).
	//
	// Type: string
	//
	// Examples:
	//   'WildFly Full 21.0.0.Final (WildFly Core 13.0.1.Final) - 2.2.2.Final'
	Description func(value string) kvp.Field
}

// Resource describing the packaged software running the application code. Web engines are typically
// executed using process.runtime.
var WebengineResource = webengineResource{
	Name: func(value string) kvp.Field {
		return kvp.String("webengine.name", value)
	},

	Version: func(value string) kvp.Field {
		return kvp.String("webengine.version", value)
	},

	Description: func(value string) kvp.Field {
		return kvp.String("webengine.description", value)
	},
}
