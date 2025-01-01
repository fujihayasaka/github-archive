package launchconfig

import (
	"github.com/pkg/errors"
)

// AppEnv defines our application runtime environment
type AppEnv string

// If adding a new environment, make sure to update azp_resources.go to properly archive/delete and check for deleted
// entities from all runtime environments.
const (
	ProductionAppEnv  AppEnv = "production"
	LabAppEnv         AppEnv = "lab"
	DevelopmentAppEnv AppEnv = "development"
	TestAppEnv        AppEnv = "test"
)

func (env AppEnv) String() string {
	return string(env)
}

func ParseEnv(s string) (AppEnv, error) {
	if s == ProductionAppEnv.String() {
		return ProductionAppEnv, nil
	}
	if s == LabAppEnv.String() {
		return LabAppEnv, nil
	}
	if s == DevelopmentAppEnv.String() {
		return DevelopmentAppEnv, nil
	}
	if s == TestAppEnv.String() {
		return TestAppEnv, nil
	}
	return "", errors.Errorf("%q is not a valid app environment", s)
}

// IsDevelopment returns true when running as local dev
func (env AppEnv) IsDevelopment() bool {
	return env == DevelopmentAppEnv
}

// IsLab returns true if app is running in lab
func (env AppEnv) IsLab() bool {
	return env == LabAppEnv
}
