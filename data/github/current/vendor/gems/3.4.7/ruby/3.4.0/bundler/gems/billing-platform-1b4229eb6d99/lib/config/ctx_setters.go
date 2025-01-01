package config

import "context"

type ApiMetricNameKey string

// TODO : we could figure the name  by inspect
// TODO : add unique key for all API calls
const (
	NetUsageKey          ApiMetricNameKey = "usageApiGetNetUsageLineItemsRUs"
	GetUsageChartDataKey ApiMetricNameKey = "usageApiGetUsageChartDataRUs"
)

func CreateContextWithApiMetricName(ctx context.Context, key ApiMetricNameKey) context.Context {
	// This should be call once per request to initialize the api metric key
	ruCount := make(map[int]float32)
	ruCount[1] = 0.0
	ctx = context.WithValue(ctx, key, ruCount)
	return ctx
}

func IncrementApiLevelRequestUsage(ctx context.Context, value float32) context.Context {
	// If a known api level metric key exists in current context, it gets incremented by the value
	knownApiMetricKeys := []ApiMetricNameKey{NetUsageKey, GetUsageChartDataKey}
	for _, key := range knownApiMetricKeys {
		existingValue, ok := ctx.Value(key).(map[int]float32)
		if ok {
			existingValue[1] += value
		}
	}
	return ctx
}

func GetApiLevelRequestUsage(ctx context.Context, key ApiMetricNameKey) float32 {
	if ruCount, ok := ctx.Value(key).(map[int]float32); ok {
		return ruCount[1]
	}
	return 0
}
