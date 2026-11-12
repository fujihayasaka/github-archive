package log

import (
	"context"
	"fmt"
	"os"
	"runtime"
	"strings"
	"time"

	version "github.com/github/github-telemetry-go"
	"github.com/go-errors/errors"
	"github.com/rs/xid"
	zaplogfmt "github.com/sykesm/zap-logfmt"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/sdk/resource"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

type outputFormat int

const (
	outputFormatLogFmt outputFormat = iota
	outputFormatJSON
	outputFormatConsole
)

type precision int

const (
	precisionNanosecond precision = iota
	precisionSecond
	precisionMillisecond
)

func (p precision) format() string {
	switch p {
	case precisionNanosecond:
		return time.RFC3339Nano
	case precisionMillisecond:
		return "2006-01-02T15:04:05.999Z07:00" // RFC3339 but with milliseconds.
	case precisionSecond:
		return time.RFC3339
	default:
		// should never happen; programmer has manually constructed an invalid precision value
		panic(fmt.Sprintf("invalid precision: %d", p))
	}
}

type timezone int

const (
	timezoneUTC timezone = iota
	timezoneLocal
)

func (tz timezone) localize() func(time.Time) time.Time {
	switch tz {
	case timezoneUTC:
		return func(t time.Time) time.Time {
			return t.UTC()
		}
	case timezoneLocal:
		return func(t time.Time) time.Time {
			return t.Local() //nolint:gosmopolitan // User is asking for local time
		}
	default:
		panic(fmt.Sprintf("invalid timezone: %d", tz))
	}
}

// defaultIncludeResources is the default set of resources that will be logged with each log entry.
var defaultIncludeResources = map[string]struct{}{
	"service.name":           {},
	"service.version":        {},
	"service.instance.id":    {},
	"deployment.environment": {},
	"telemetry.sdk.name":     {},
	"gh.sdk.name":            {},
	"gh.sdk.version":         {},
}

func wrapWithResources(lc *Config, logger *zap.Logger) *zap.Logger {
	fields := []zap.Field{}

	for _, attr := range lc.resource.Attributes() {
		key := string(attr.Key)
		if _, ok := lc.includeResourceAttributes[key]; ok {
			fields = append(fields, zap.String(key, attr.Value.AsString()))
		}
	}

	return logger.With(fields...)
}

// processConfig constructs a loggingConfig.
//
// The priority of settings are:
//  1. Specified in code for testing (via the opts argument)
//  2. Otherwise whatever is specified in the packed OTEL_RESOURCE_ATTRIBUTES env var. For example, the
//     deployment.environment field inside OTEL_RESOURCE_ATTRIBUTES variable is used to specify the
//     environment (development or production).
//  3. Otherwise library-specific environment variables (which have been parsed into the config argument)
//  4. Otherwise user-provided options passed via userConfig and opts
//  5. Otherwise fall back to the hard-coded defaults
func processConfig(userConfig *Config, opts ...Option) (*logger, error) {
	// The sane way to deal with multi-level configs is to process them in reverse, overwriting the
	// hard-coded defaults with the higher priority choices.

	// ------------------------------------------------------------------------
	// Hard-coded defaults
	cfg := Config{
		environment:               "development",
		outputFormat:              outputFormatLogFmt,
		level:                     InfoLevel,
		includeResourceAttributes: defaultIncludeResources,
		precision:                 precisionNanosecond,
		timezone:                  timezoneUTC,
		sdkname:                   version.GlobalSDKName,
		sdkversion:                version.GlobalSDKVersion,
	}

	// ------------------------------------------------------------------------
	// Set user provided options on the provided user config
	for _, opt := range opts {
		if opt != nil {
			opt(userConfig)
		}
	}

	// ------------------------------------------------------------------------
	// Library-specific environment variables override hard-coded defaults

	// GITHUB_TELEMETRY_ENVIRONMENT
	// Can be an arbitrary string. Can be overridden by values provided in OTEL_RESOURCE_ATTRIBUTES
	// (which could be injected by kubernetes in moda).
	if userConfig.Environment != "" {
		cfg.environment = userConfig.Environment
	}

	// GITHUB_TELEMETRY_LOGS_CONSOLE_ENCODING
	switch userConfig.LogConsoleEncoding {
	case "json":
		cfg.outputFormat = outputFormatJSON
	case "logfmt":
		cfg.outputFormat = outputFormatLogFmt
	case "console":
		cfg.outputFormat = outputFormatConsole
	case "syslog":
		return nil, errors.New("unsupported value 'syslog' for GITHUB_TELEMETRY_LOGS_CONSOLE_ENCODING, please select: 'json', 'logfmt' or 'console'")
	case "":
		// unset, will stay with the default from `cfg` defined above
	default:
		return nil, fmt.Errorf("unrecognized value for GITHUB_TELEMETRY_LOGS_CONSOLE_ENCODING: %v", userConfig.LogConsoleEncoding)
	}

	// GITHUB_TELEMETRY_LOGS_INCLUDE_RESOURCE_ATTRIBUTES
	if userConfig.LogIncludeResourceAttributes != "<DEFAULT>" {
		cfg.includeResourceAttributes = map[string]struct{}{}
		attrs := strings.FieldsFunc(userConfig.LogIncludeResourceAttributes, func(r rune) bool {
			return strings.ContainsRune(" ,", r)
		})
		for _, attr := range attrs {
			cfg.includeResourceAttributes[attr] = struct{}{}
		}
	}

	// GITHUB_TELEMETRY_LOGS_LEVEL
	switch strings.ToLower(userConfig.LogLevel) {
	case DebugLevel.String():
		cfg.level = DebugLevel
	case InfoLevel.String():
		cfg.level = InfoLevel
	case WarnLevel.String():
		cfg.level = WarnLevel
	case ErrorLevel.String():
		cfg.level = ErrorLevel
	case FatalLevel.String():
		cfg.level = FatalLevel
	case "":
		// unset, will stay with the default from `cfg` defined above
	default:
		return nil, fmt.Errorf("unrecognized value for GITHUB_TELEMETRY_LOGS_LEVEL: %v", userConfig.LogLevel)
	}

	// GITHUB_TELEMETRY_LOGS_PRECISION
	switch userConfig.LogPrecision {
	case "nanosecond":
		cfg.precision = precisionNanosecond
	case "second":
		cfg.precision = precisionSecond
	case "millisecond":
		cfg.precision = precisionMillisecond
	case "":
		// unset, will stay with the default from `cfg` defined above
	default:
		return nil, fmt.Errorf("unrecognized value for GITHUB_TELEMETRY_LOGS_PRECISION: %v", userConfig.LogPrecision)
	}

	// GITHUB_TELEMETRY_LOGS_TZ
	switch userConfig.LogTimezone {
	case "utc":
		cfg.timezone = timezoneUTC
	case "local":
		cfg.timezone = timezoneLocal
	case "":
		// unset, will stay with the default from `cfg` defined above
	default:
		return nil, fmt.Errorf("unrecognized value for GITHUB_TELEMETRY_LOGS_TZ: %v", userConfig.LogTimezone)
	}

	// ------------------------------------------------------------------------

	// OTEL_RESOURCE_ATTRIBUTES override library-specific environment variables
	for _, kv := range resource.Environment().Attributes() {
		switch {
		case kv.Key == attribute.Key("deployment.environment"):
			// deployment.environment subkey overrides value from GITHUB_TELEMETRY_ENVIRONMENT
			if val := kv.Value.AsString(); val != "" {
				cfg.environment = val
			}
		case kv.Key == attribute.Key("service.name"):
			if val := kv.Value.AsString(); val != "" {
				cfg.serviceName = &val
			}
		case kv.Key == attribute.Key("service.version"):
			if val := kv.Value.AsString(); val != "" {
				cfg.serviceVersion = &val
			}
		}
	}

	// ------------------------------------------------------------------------
	// Passed-in options override everything else (done by tests)
	for _, opt := range opts {
		if opt != nil {
			opt(&cfg)
		}
	}

	// ------------------------------------------------------------------------
	// FIXUPS
	if cfg.instanceID == "" {
		cfg.instanceID = xid.New().String()
	}

	// More fixups
	logger := configureLogger(&cfg)

	// Internal logging
	logger.Named("Telemetry").Debug("Logging initialized")

	return logger, nil
}

func getDefaultEncoderConfig() zapcore.EncoderConfig {
	config := zap.NewProductionEncoderConfig()

	config.MessageKey = OtelFieldBody
	config.TimeKey = OtelFieldTimestamp
	config.LevelKey = OtelFieldSeverityText
	config.NameKey = OtelFieldInstrumentationScope
	config.EncodeLevel = zapcore.CapitalLevelEncoder

	return config
}

func mapResources(r *resource.Resource, cfg *Config) *resource.Resource {
	attrs := []attribute.KeyValue{
		attribute.String("service.instance.id", cfg.instanceID),
		attribute.String("process.runtime.version", runtime.Version()),
		attribute.String("deployment.environment", cfg.environment),
		attribute.String("gh.sdk.name", cfg.sdkname),
		attribute.String("gh.sdk.version", cfg.sdkversion),
	}
	if cfg.serviceName != nil {
		attrs = append(attrs, attribute.Key("service.name").String(*cfg.serviceName))
	}
	if cfg.serviceVersion != nil {
		attrs = append(attrs, attribute.Key("service.version").String(*cfg.serviceVersion))
	}

	if cfg.environment != "" {
		attrs = append(attrs, attribute.String("deployment.environment", cfg.environment))
	}

	attrs = append(r.Attributes(), attrs...)

	// Add the hostname to the resource
	hostNameResource, _ := resource.New(context.Background(), resource.WithHost())
	attrs = append(attrs, hostNameResource.Attributes()...)

	return resource.NewWithAttributes(r.SchemaURL(), attrs...)
}

// configureLogger is a private function called by processConfig and WithLevel.
//
// It is not called from Named or With because those receivers modify the underlying zap
// logger, whereas WithLevel and processConfig modify our configuration.
func configureLogger(cfg *Config, opts ...Option) *logger {
	cfg = cfg.clone()

	for _, opt := range opts {
		opt(cfg)
	}

	cfg.resource = mapResources(resource.Default(), cfg)
	mapper := newOpenTelemetryMapper(cfg.resource)

	zapLevel := zap.NewAtomicLevelAt(toZapCoreLevel(cfg.level))

	if cfg.encoder == nil {
		encoderConfig := getDefaultEncoderConfig()

		// set time encoder by timezone and precision
		encoderConfig.EncodeTime = encodeTimeFunc(cfg.timezone, cfg.precision)
		encoderConfig.EncodeDuration = encodeDurationFunc(cfg.durationFormat)

		// output format
		switch cfg.outputFormat {
		case outputFormatJSON:
			enc := zapcore.NewJSONEncoder(encoderConfig)
			cfg.encoder = &enc
		case outputFormatConsole:
			enc := zapcore.NewConsoleEncoder(encoderConfig)
			cfg.encoder = &enc
		default:
			enc := zaplogfmt.NewEncoder(encoderConfig)
			cfg.encoder = &enc
		}
	}

	if cfg.writeSyncer == nil {
		cfg.writeSyncer = os.Stdout
	}

	consolecore := zapcore.NewCore(*cfg.encoder, cfg.writeSyncer, zapLevel)

	if !cfg.isSetup {
		cfg.isSetup = true

		attrs := mapper.resources
		fields := []zapcore.Field{}
		for k, v := range attrs {
			fields = append(fields, zap.String(k, v))
		}

		l := zap.New(consolecore)
		l.Named("Telemetry").Debug("Resources Detected", fields...)
	}

	zapLogger := zap.New(zapcore.NewTee(consolecore))
	zapLogger = wrapWithResources(cfg, zapLogger)

	return &logger{config: cfg, zapLogger: zapLogger, zapLevel: zapLevel}
}

// Helpers

func toZapCoreLevel(level Level) zapcore.Level {
	switch level {
	case DebugLevel:
		return zapcore.DebugLevel
	case ErrorLevel:
		return zapcore.ErrorLevel
	case FatalLevel:
		return zapcore.FatalLevel
	case InfoLevel:
		return zapcore.InfoLevel
	case WarnLevel:
		return zapcore.WarnLevel
	default:
		return zapcore.InfoLevel
	}
}

// encodeTimeFunc returns an appropriate function used to encode time given a
// precision and a timezone.
func encodeTimeFunc(tz timezone, prec precision) func(ts time.Time, encoder zapcore.PrimitiveArrayEncoder) {
	localize := tz.localize()
	return func(ts time.Time, encoder zapcore.PrimitiveArrayEncoder) {
		encoder.AppendString(localize(ts).Format(prec.format()))
	}
}

func encodeDurationFunc(df DurationFormat) zapcore.DurationEncoder {
	switch df {
	case DurationFormatFractionalSeconds:
		return zapcore.SecondsDurationEncoder
	case DurationFormatMillis:
		return zapcore.MillisDurationEncoder
	case DurationFormatNanos:
		return zapcore.NanosDurationEncoder
	case DurationFormatString:
		return zapcore.StringDurationEncoder
	default:
		panic(fmt.Sprintf("invalid duration format: %d", df))
	}
}
