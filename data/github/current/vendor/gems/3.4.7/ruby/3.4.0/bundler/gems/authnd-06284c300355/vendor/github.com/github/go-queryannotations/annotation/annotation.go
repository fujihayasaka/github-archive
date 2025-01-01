package annotation

import "context"

type Annotation struct {
	Key   string
	Value string
}

const (
	ApplicationKey    = "application"
	DeployedToKey     = "deployed_to"
	CategoryKey       = "category"
	CatalogServiceKey = "catalog_service"
	PackageKey        = "package"
	JobKey            = "job"
	JobIDKey          = "job_id"
	NameKey           = "name"
	RouteKey          = "route"
	RequestIDKey      = "request_id"
	ServerKey         = "server"
)

type AnnotationOption func(context.Context) *Annotation

func Application(application string) AnnotationOption {
	return keyValue(ApplicationKey, application)
}

func DeployedTo(deployedTo string) AnnotationOption {
	return keyValue(DeployedToKey, deployedTo)
}

func Category(category string) AnnotationOption {
	return keyValue(CategoryKey, category)
}

func CatalogService(catalogService string) AnnotationOption {
	return keyValue(CatalogServiceKey, catalogService)
}

func Package(packageName string) AnnotationOption {
	return keyValue(PackageKey, packageName)
}

func Job(job string) AnnotationOption {
	return keyValue(JobKey, job)
}

func JobID(jobID string) AnnotationOption {
	return keyValue(JobIDKey, jobID)
}

func Name(name string) AnnotationOption {
	return keyValue(NameKey, name)
}

func Route(route string) AnnotationOption {
	return keyValue(RouteKey, route)
}

func RequestID(requestID string) AnnotationOption {
	return keyValue(RequestIDKey, requestID)
}

func Server(server string) AnnotationOption {
	return keyValue(ServerKey, server)
}

func Component(Key, value string) AnnotationOption {
	return keyValue(Key, value)
}

func keyValue(key, value string) AnnotationOption {
	return func(ctx context.Context) *Annotation {
		return &Annotation{
			Key:   key,
			Value: value,
		}
	}
}
