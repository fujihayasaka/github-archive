package main

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"sort"
	"strings"

	"github.com/github/launch/pkg/abreaker"
)

var rateBreakerBuilders = []abreaker.RateBreakerBuilder{
	abreaker.BuildGitHubClientConfig,
	abreaker.BuildGitHubTwirpClientConfig,
	abreaker.BuildGitHubTwirpBillingClientConfig,
	abreaker.BuildAzpRepoClientConfig,
	abreaker.BuildJobCLIAZPClientConfig,
	abreaker.BuildAzpBearerTokenConfig,
	abreaker.BuildAzpKeyVaultConfig,
	abreaker.BuildRedisConfig,
	abreaker.BuildRedisReceiverConfig,
	abreaker.BuildAqueductDeployerClientConfig,
	abreaker.BuildAqueductWorkerClientConfig,
	abreaker.BuildSpokesdClientConfig,
	abreaker.BuildDeployerTwirpClientConfig,
	abreaker.BuildFrenoClientConfig,
	abreaker.BuildKredzTwirpClientConfig,
	abreaker.BuildVarzTwirpClientConfig,
	abreaker.BuildResultsTwirpClientConfig,
	abreaker.BuildBillingPlatformTwirpClientConfig,
	abreaker.BuildNetworkServiceClientConfig,
}

var consecutiveBreakerBuilders = []abreaker.ConsecutiveBreakerBuilder{
	abreaker.BuildAzpS2SConfig,
	abreaker.BuildLaunchDBClientConfig,
	abreaker.BuildLaunchRODBClientConfig,
	abreaker.BuildPayloadsClientConfig,
	abreaker.BuildJobCLITokenServiceConfig,
	abreaker.BuildAuthzdClientConfig,
}

type dashboard struct {
	Title             string                      `json:"title"`
	Description       string                      `json:"description"`
	Widgets           []*widget                   `json:"widgets"`
	TemplateVariables []dashboardTemplateVariable `json:"template_variables,omitempty"`
	LayoutType        string                      `json:"layout_type"`
	IsReadOnly        bool                        `json:"is_read_only"`
	NotifyList        []any                       `json:"notify_list"`
	ReflowType        string                      `json:"reflow_type"`
	ID                string                      `json:"id"`
}

type dashboardTemplateVariable struct {
	Name            string   `json:"name"`
	Default         string   `json:"default"`
	Prefix          string   `json:"prefix"`
	AvailableValues []string `json:"available_values"`
}

type widget struct {
	ID         int64            `json:"id"`
	Definition widgetDefinition `json:"definition"`
}

type widgetDefinition struct {
	Title      string           `json:"title,omitempty"`
	TitleSize  string           `json:"title_size,omitempty"`
	TitleAlign string           `json:"title_align,omitempty"`
	ShowLegend bool             `json:"show_legend,omitempty"`
	Type       string           `json:"type"`
	Requests   []widgetRequests `json:"requests,omitempty"`
	YAxis      *widgetYAxis     `json:"yaxis,omitempty"`
	Markers    []widgetMarker   `json:"markers,omitempty"`
	Content    string           `json:"content,omitempty"`
	LayoutType string           `json:"layout_type,omitempty"`
	Widgets    []*widget        `json:"widgets,omitempty"`
	Events     []widgetEvent    `json:"events,omitempty"`
}

type widgetEvent struct {
	Q string `json:"q"`
}

type widgetRequests struct {
	Formulas       []widgetFormula `json:"formulas,omitempty"`
	ResponseFormat string          `json:"response_format"`
	Queries        []widgetQuery   `json:"queries"`
	Style          widgetStyle     `json:"style"`
	DisplayType    string          `json:"display_type,omitempty"`
}

type widgetFormula struct {
	Formula string `json:"formula"`
}

type widgetQuery struct {
	Query      string `json:"query"`
	DataSource string `json:"data_source"`
	Name       string `json:"name"`
}

type queryFilterOptions struct {
	useEnvTemplate bool
}

var queryFilterOptionsDefault = &queryFilterOptions{
	useEnvTemplate: true,
}

// nolint:unparam
func buildQueryString(filterOptions *queryFilterOptions) string {
	var qf []string
	if filterOptions == nil {
		filterOptions = queryFilterOptionsDefault
	}
	if filterOptions.useEnvTemplate {
		qf = append(qf, "$launch_env,$deployed_to,$host")
	}
	if len(qf) > 0 {
		return strings.Join(qf, ",")
	}
	return "*"
}

type widgetStyle struct {
	Palette string `json:"palette"`
}

type widgetYAxis struct {
	Min         string `json:"min,omitempty"`
	Max         string `json:"max,omitempty"`
	Scale       string `json:"scale,omitempty"`
	IncludeZero bool   `json:"include_zero,omitempty"`
}

type widgetMarker struct {
	Value string `json:"value"`
	Type  string `json:"display_type"`
	Label string `json:"label"`
}

func GenerateRateBreakerMinSampleWidget(cfg *abreaker.RateBreakerConfig) *widget {
	return &widget{
		ID: rand.Int63(),
		Definition: widgetDefinition{
			Title:      fmt.Sprintf("%s - Sample Threshold", cfg.Name),
			TitleSize:  "16",
			TitleAlign: "left",
			ShowLegend: true,
			Type:       "timeseries",
			YAxis: &widgetYAxis{
				Scale: "log",
				Min:   "1e-9",
				Max:   "1e12",
			},
			Requests: []widgetRequests{
				{
					Formulas: []widgetFormula{
						{
							Formula: "success + failure",
						},
					},
					ResponseFormat: "timeseries",
					Queries: []widgetQuery{
						{
							Query:      fmt.Sprintf("sum:launch.circuit.%s.successes{%s} by {host}.rollup(sum, %d)", cfg.Name, buildQueryString(nil), cfg.WindowSize),
							DataSource: "metrics",
							Name:       "success",
						},
						{
							Query:      fmt.Sprintf("sum:launch.circuit.%s.failures{%s} by {host}.rollup(sum, %d)", cfg.Name, buildQueryString(nil), cfg.WindowSize),
							DataSource: "metrics",
							Name:       "failure",
						},
					},
					Style: widgetStyle{
						Palette: "cool",
					},
				},
			},
			Markers: []widgetMarker{
				{
					Value: fmt.Sprintf("0 < y < %d", cfg.Min),
					Type:  "warning bold",
					Label: "BelowMinSampleThreshold",
				},
			},
		},
	}
}

func GenerateRateBreakerRateThresholdWidget(cfg *abreaker.RateBreakerConfig) *widget {
	return &widget{
		ID: rand.Int63(),
		Definition: widgetDefinition{
			Title:      fmt.Sprintf("%s - Error Rate", cfg.Name),
			TitleSize:  "16",
			TitleAlign: "left",
			ShowLegend: true,
			Type:       "timeseries",
			YAxis: &widgetYAxis{
				Scale: "log",
				Min:   "1e-9",
				Max:   "1e12",
			},
			Requests: []widgetRequests{
				{
					Formulas: []widgetFormula{
						{
							Formula: "error_rate",
						},
					},
					ResponseFormat: "timeseries",
					Queries: []widgetQuery{
						{
							Query:      fmt.Sprintf("sum:launch.circuit.%s.error_rate{%s} by {host}", cfg.Name, buildQueryString(nil)),
							DataSource: "metrics",
							Name:       "error_rate",
						},
					},
					Style: widgetStyle{
						Palette: "cool",
					},
					DisplayType: "bars",
				},
			},
			Events: []widgetEvent{
				{
					Q: fmt.Sprintf("tags:type:circuitbreaker,app:launch,state:tripped,name:%s", cfg.Name),
				},
			},
			Markers: []widgetMarker{
				{
					Value: fmt.Sprintf("y = %d", int(cfg.Rate*100)),
					Type:  "error dashed",
					Label: "ErrorRateThreshold",
				},
			},
		},
	}
}

func GenerateRateBreakerGroup(cfg *abreaker.RateBreakerConfig) *widget {
	var w []*widget
	w = append(w, GenerateRateBreakerRateThresholdWidget(cfg))
	w = append(w, GenerateRateBreakerMinSampleWidget(cfg))
	return NewWidgetGroup(fmt.Sprintf("RateBreaker - %s", cfg.Name), w)
}

func GenerateConsecutiveBreakerGroup(cfg *abreaker.ConsecutiveBreakerConfig) *widget {
	var w []*widget
	w = append(w, GenerateConsecutiveErrorWidget(cfg)...)
	return NewWidgetGroup(fmt.Sprintf("ConsecutiveErrorBreaker - %s", cfg.Name), w)
}

func GenerateConsecutiveErrorWidget(cfg *abreaker.ConsecutiveBreakerConfig) []*widget {
	return []*widget{
		{
			ID: rand.Int63(),
			Definition: widgetDefinition{
				Title:      fmt.Sprintf("%s - Errors (Must be consecutive)", cfg.Name),
				TitleSize:  "16",
				TitleAlign: "left",
				ShowLegend: true,
				Type:       "timeseries",
				YAxis: &widgetYAxis{
					Scale: "log",
					Min:   "1e-9",
					Max:   "1e12",
				},
				Requests: []widgetRequests{
					{
						ResponseFormat: "timeseries",
						Queries: []widgetQuery{
							{
								Query:      fmt.Sprintf("sum:launch.circuit.%s.failures{%s} by {host}", cfg.Name, buildQueryString(nil)),
								DataSource: "metrics",
								Name:       "failures",
							},
						},
						Style: widgetStyle{
							Palette: "cool",
						},
						DisplayType: "bars",
					},
				},
				Events: []widgetEvent{
					{
						Q: fmt.Sprintf("tags:type:circuitbreaker,app:launch,state:tripped,name:%s", cfg.Name),
					},
				},
				Markers: []widgetMarker{
					{
						Value: fmt.Sprintf("y = %d", int(cfg.Threshold)),
						Type:  "error dashed",
						Label: "ConsecutiveErrorThreshold",
					},
				},
			},
		},
		{
			ID: rand.Int63(),
			Definition: widgetDefinition{
				Title:      fmt.Sprintf("%s - Successes", cfg.Name),
				TitleSize:  "16",
				TitleAlign: "left",
				ShowLegend: true,
				Type:       "timeseries",
				YAxis: &widgetYAxis{
					Scale: "log",
					Min:   "1e-9",
					Max:   "1e12",
				},
				Requests: []widgetRequests{
					{
						ResponseFormat: "timeseries",
						Queries: []widgetQuery{
							{
								Query:      fmt.Sprintf("sum:launch.circuit.%s.successes{%s} by {host}", cfg.Name, buildQueryString(nil)),
								DataSource: "metrics",
								Name:       "successes",
							},
						},
						Style: widgetStyle{
							Palette: "cool",
						},
					},
				},
				Events: []widgetEvent{
					{
						Q: fmt.Sprintf("tags:type:circuitbreaker,app:launch,state:tripped,name:%s", cfg.Name),
					},
				},
			},
		},
	}
}

func NewWidgetGroup(title string, widgets []*widget) *widget {
	return &widget{
		ID: rand.Int63(),
		Definition: widgetDefinition{
			Title:      title,
			Type:       "group",
			LayoutType: "ordered",
			Widgets:    widgets,
		},
	}
}

func GenerateCircuitBreakerTuningDashboard(cfg abreaker.Config) (string, error) {
	var widgets []*widget

	// Generate Rate Breaker Widgets
	for _, builder := range rateBreakerBuilders {
		bcfg := builder(cfg)
		w := GenerateRateBreakerGroup(bcfg)
		widgets = append(widgets, w)
	}

	// Generate Consecutive Breaker Widgets
	for _, builder := range consecutiveBreakerBuilders {
		ccfg := builder(cfg)
		w := GenerateConsecutiveBreakerGroup(ccfg)
		widgets = append(widgets, w)
	}

	// Sort widgets by title so the ordering is predictable
	sort.Slice(widgets, func(i, j int) bool { return widgets[i].Definition.Title < widgets[j].Definition.Title })

	d := dashboard{
		Title: "Circuit Breaker Tuning",
		// We use the dashboard description to enable automation. See https://thehub.github.com/engineering/development-and-ops/observability/datadog/dashboards/#dashboard-metadata
		Description: "```\nmetadata\nmanaged: true\nservice: github/c2c-actions-experience\n```",
		Widgets:     widgets,
		LayoutType:  "ordered",
		ReflowType:  "auto",
		TemplateVariables: []dashboardTemplateVariable{
			{
				Name:    "deployed_to",
				Default: "production",
				Prefix:  "deployed_to",
			},
			{
				Name:    "launch_env",
				Default: "production",
				Prefix:  "launch_env",
			},
			{
				Name:    "host",
				Default: "*",
				Prefix:  "host",
			},
		},
	}

	jsonDashboard, err := json.Marshal(d)
	if err != nil {
		return "", err
	}

	return string(jsonDashboard), nil
}
