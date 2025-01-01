package types

func NewByteAttribute(key []byte, value *Attribute_ByteValue) *Attribute {
	return &Attribute{
		Key:   key,
		Value: value,
	}
}

func NewBoolAttribute(key []byte, value *Attribute_BoolValue) *Attribute {
	return &Attribute{
		Key:   key,
		Value: value,
	}
}
