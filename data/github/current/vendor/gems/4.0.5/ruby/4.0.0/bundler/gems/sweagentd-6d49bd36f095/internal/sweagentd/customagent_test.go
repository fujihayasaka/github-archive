package sweagentd

import (
	"reflect"
	"testing"
)

func TestCustomAgentTriggersHasDefinedTriggers(t *testing.T) {
	if got := (CustomAgentTriggers{}).HasDefinedTriggers(); got {
		t.Fatalf("HasDefinedTriggers() = %v, want false", got)
	}

	triggers := CustomAgentTriggers{
		Issues: &CustomAgentTrigger{Types: []string{}},
	}
	if got := triggers.HasDefinedTriggers(); !got {
		t.Fatalf("HasDefinedTriggers() = %v, want true", got)
	}
}

func TestCustomAgentTriggersHasDefinedTriggers_CoversAllTriggerFields(t *testing.T) {
	triggerType := reflect.TypeFor[CustomAgentTriggers]()

	for i := 0; i < triggerType.NumField(); i++ {
		fieldType := triggerType.Field(i)
		t.Run(fieldType.Name, func(t *testing.T) {
			if fieldType.Type.Kind() != reflect.Ptr {
				t.Fatalf("CustomAgentTriggers.%s must be a pointer field for this guard test", fieldType.Name)
			}

			triggersValue := reflect.New(triggerType).Elem()
			triggersValue.Field(i).Set(reflect.New(fieldType.Type.Elem()))

			triggers := triggersValue.Interface().(CustomAgentTriggers)
			if !triggers.HasDefinedTriggers() {
				t.Fatalf("HasDefinedTriggers() = false when %s is set; update HasDefinedTriggers for new trigger fields", fieldType.Name)
			}
		})
	}
}
