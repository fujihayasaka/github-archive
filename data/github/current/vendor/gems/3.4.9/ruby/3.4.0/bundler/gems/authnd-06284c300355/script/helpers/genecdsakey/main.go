package main

import (
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"os"
	"path/filepath"

	"github.com/github/authnd/internal/common/crypto"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: genecdsakey <output-dir>")
		os.Exit(1)
	}
	path := filepath.Clean(os.Args[1])

	privateKeyPath := path + ".pem"
	publicKeyPath := path + ".pub"
	fingerprintPath := path + "-pk-fingerprint.txt"

	privateKey := crypto.MustCreateECDSAPrivateKey()
	publicKey := crypto.MustGetBase64EncodedPublicKey(privateKey)
	publicKeyFingerprint := crypto.MustGenerateECDSAFingerprint(publicKey)

	privateKeyBytes, err := x509.MarshalECPrivateKey(privateKey)
	if err != nil {
		panic(err)
	}
	privateKeyPEM := &pem.Block{
		Type:  "EC PRIVATE KEY",
		Bytes: privateKeyBytes,
	}
	privateKeyFile := createFile(privateKeyPath)
	defer privateKeyFile.Close()

	if err := pem.Encode(privateKeyFile, privateKeyPEM); err != nil {
		fmt.Print(err)
	}
	fmt.Println("private key written to", privateKeyPath)

	publicKeyFile := createFile(publicKeyPath)
	defer publicKeyFile.Close()

	_, err = publicKeyFile.WriteString(publicKey)
	if err != nil {
		panic(err)
	}
	fmt.Println("public key written to", publicKeyPath)

	publicKeyFingerprintFile := createFile(fingerprintPath)
	defer publicKeyFingerprintFile.Close()

	_, err = publicKeyFingerprintFile.WriteString(publicKeyFingerprint)
	if err != nil {
		panic(err)
	}
	fmt.Println("fingerprint written to", fingerprintPath)
}

func createFile(path string) *os.File {
	dir := filepath.Dir(path)

	_, err := os.Stat(dir)
	if os.IsNotExist(err) {
		err := os.Mkdir(dir, 0777)
		if err != nil {
			panic(err)
		}
	}

	f, err := os.Create(path)
	if err != nil {
		panic(err)
	}
	return f
}
