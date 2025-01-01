package identity

// TODO(zacharysierakowski): We could eventually add more context here like the owner/creator
// of the key, so that app logic can quickly make decisions like if the key was created by an application
type SSHPublicKeyContext struct {
	PublicKeyID uint64
}
