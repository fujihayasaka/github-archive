package hydro

import (
	"fmt"
	"strings"

	"google.golang.org/protobuf/proto"
)

// DefaultTopicFormat is the default TopicFormat used by a Publisher when
// formatting the topic an event will be published to.
const DefaultTopicFormat = TopicFormatV2

// TopicFormat defines a topic format version that is used when formatting a
// Hydro topic name.
//
// See the defined TopicFormat constants for details about their format.
type TopicFormat int

const (
	// TopicFormatV1 composes a topic name using the legacy Hydro topic naming
	// scheme "site.namespace.schema_name".
	//
	// The site and namespace components are provided by the Publisher,
	// defaulting to "cp1-iad" and "ingest". The schema_name component is
	// formatted using the same behavior as TopicFormatV2.
	//
	// When publishing an event using the WithTopic PublishOption, its value
	// will only override the schema_name component.
	TopicFormatV1 TopicFormat = iota + 1

	// TopicFormatV2 composes a topic name from a proto.Message using the
	// abbreviated schema name format, "package.MessageType", omitting the
	// "hydro.schemas." package prefix.
	//
	// For example, the topic for a proto.Message with the name
	// "hydro.schemas.github.test.v0.TestMessage" would be
	// "github.test.v0.TestMessage".
	//
	// When publishing an event using the WithTopic PublishOption, its value
	// will be used as the topic name instead.
	TopicFormatV2
)

func (tf TopicFormat) validate() error {
	switch tf {
	case TopicFormatV1:
	case TopicFormatV2:
	default:
		return fmt.Errorf("unsupported topic format: %d", tf)
	}
	return nil
}

type topicFormatError struct {
	Reason string
}

func (err *topicFormatError) Error() string {
	return "error formatting topic: " + err.Reason
}

type topicFormatter struct {
	version TopicFormat

	// TopicFormatV1 fields
	site      string
	namespace string
}

func defaultTopicFormatter() topicFormatter {
	return topicFormatter{
		version: DefaultTopicFormat,
	}
}

func (tf topicFormatter) Format(msg proto.Message, override string) (string, error) {
	var out string

	switch tf.version {
	case TopicFormatV1:
		var err error
		out, err = tf.formatV1(msg, override)
		if err != nil {
			return "", err
		}
	case TopicFormatV2:
		out = tf.formatV2(msg, override)
	}

	if out == "" {
		return "", &topicFormatError{Reason: "empty topic"}
	}

	return out, nil
}

func (tf topicFormatter) formatV1(msg proto.Message, override string) (string, error) {
	if tf.site == "" {
		return "", &topicFormatError{Reason: "empty site"}
	}
	if tf.namespace == "" {
		return "", &topicFormatError{Reason: "empty namespace"}
	}

	schema := abbreviateSchemaName(msg, override)
	if schema == "" {
		return "", &topicFormatError{Reason: "empty schema name"}
	}

	return tf.site + "." + tf.namespace + "." + schema, nil
}

func (tf topicFormatter) formatV2(msg proto.Message, override string) string {
	return abbreviateSchemaName(msg, override)
}

func abbreviateSchemaName(msg proto.Message, override string) string {
	if override != "" {
		return override
	}
	return strings.Replace(string(proto.MessageName(msg)), "hydro.schemas.", "", 1)
}
