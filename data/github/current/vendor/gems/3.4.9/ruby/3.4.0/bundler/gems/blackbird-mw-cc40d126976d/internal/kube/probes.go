package kube

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/github/blackbird-mw/internal/env"
)

type kubeResponse struct {
	DeployedSHA string `json:"deployed_sha"`
	DeployedRef string `json:"deployed_ref"`
	Message     string `json:"message"`
}

// ready returns an HTTP response when the service is ready to serve traffic. Kubernetes uses this to determine when to put a pod into service.
//
// See:
// https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-readiness-probes
func Ready(config env.Config) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		resp, err := json.Marshal(kubeResponse{
			DeployedSHA: config.GetDeployedSHA(),
			DeployedRef: config.GetDeployedRef(),
			Message:     fmt.Sprintf("%s: ready", config.App()),
		})
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
		}

		w.Header().Set("Content-Type", "application/json")
		w.Write(resp) //nolint:gosec,errcheck
	}
}
