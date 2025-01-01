package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"os"
	"path"
)

func main() {
	baseDir := os.Getenv("HOME")
	if baseDir == "" {
		fmt.Fprintln(os.Stderr, "Could not find home directory!")
		os.Exit(1)
	}

	authndDir := path.Join(baseDir, ".authnd")
	err := os.MkdirAll(authndDir, 0700) // User: rwx, Group ---, Other ---
	if err != nil {
		panic(err)
	}

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		panic(err)
	}

	privateKeyBytes := x509.MarshalPKCS1PrivateKey(key)
	publicKeyBytes := x509.MarshalPKCS1PublicKey(&key.PublicKey)

	privateKeyFile, err := os.Create(path.Join(authndDir, "chatops.development.private.pem"))
	if err != nil {
		panic(err)
	}
	defer privateKeyFile.Close()
	err = pem.Encode(privateKeyFile, &pem.Block{Type: "RSA PRIVATE KEY", Bytes: privateKeyBytes})
	if err != nil {
		panic(err)
	}

	publicKeyFile, err := os.Create(path.Join(authndDir, "chatops.development.public.pem"))
	if err != nil {
		panic(err)
	}
	defer publicKeyFile.Close()
	err = pem.Encode(publicKeyFile, &pem.Block{Type: "RSA PUBLIC KEY", Bytes: publicKeyBytes})
	if err != nil {
		panic(err)
	}

	fmt.Println("Generated new chatops development key in ", authndDir)
}
