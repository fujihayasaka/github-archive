package kvp

type KVP struct {
	kvps []Field
}

// KVPs builds a new KVP with the given fields.
func KVPs(fields ...Field) *KVP {
	kvps := make([]Field, len(fields))
	copy(kvps, fields)

	return &KVP{
		kvps: kvps,
	}
}

// With creates a KVP with the given fields.
func (k *KVP) With(fields ...Field) *KVP {
	kvps := make([]Field, len(k.kvps)+len(fields))
	copy(kvps, k.kvps)
	copy(kvps[len(k.kvps):], fields)

	return &KVP{
		kvps: kvps,
	}
}

// Add adds fields to a KVP.
func (k *KVP) Add(fields ...Field) {
	k.kvps = append(k.kvps, fields...)
}

// Fields returns the fields.
func (k *KVP) Fields() []Field {
	return k.kvps
}

// Field attempts to find a Field with the matching key name. If no field is
// found, nil is returned.
func (k *KVP) Field(key string) *Field {
	for _, f := range k.kvps {
		f := f
		if f.Key == key {
			return &f
		}
	}
	return nil
}
