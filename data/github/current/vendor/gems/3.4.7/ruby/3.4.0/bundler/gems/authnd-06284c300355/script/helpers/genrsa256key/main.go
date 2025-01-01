package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/pem"
	"math/big"
	"os"
	"path"
	"time"
)

func main() {
	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		panic(err)
	}
	publicKey := privateKey.PublicKey

	privateKeyBytes := x509.MarshalPKCS1PrivateKey(privateKey)

	privateKeyPEM := &pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: privateKeyBytes,
	}
	privateKeyFile := createFile("rsa256-priv-key.pem")
	defer privateKeyFile.Close()

	if err := pem.Encode(privateKeyFile, privateKeyPEM); err != nil {
		panic(err)
	}

	// Generate a certificate
	template := x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject: pkix.Name{
			Organization: []string{"self-signed.github"},
		},
		NotBefore:             time.Now(),
		NotAfter:              time.Now().AddDate(0, 0, 3650), // 10 years
		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}
	derBytes, err := x509.CreateCertificate(rand.Reader, &template, &template, &publicKey, privateKey)
	if err != nil {
		panic(err)
	}

	certFile := createFile("rsa256-priv-key.crt")
	if err := pem.Encode(certFile, &pem.Block{Type: "CERTIFICATE", Bytes: derBytes}); err != nil {
		panic(err)
	}

	publicKeyFile := createFile("rsa256-key.pub")
	defer publicKeyFile.Close()

	publicKeyBytes, err := x509.MarshalPKIXPublicKey(&publicKey)
	if err != nil {
		panic(err)
	}

	_, err = publicKeyFile.WriteString(base64.StdEncoding.EncodeToString(publicKeyBytes))
	if err != nil {
		panic(err)
	}
}

func createFile(fileName string) *os.File {
	baseDir, _ := os.Getwd()
	targetDir := path.Join(baseDir, "dev")

	if os.Getenv("OUT") != "" {
		targetDir = os.Getenv("OUT")
	}

	_, err := os.Stat(targetDir)
	if os.IsNotExist(err) {
		err := os.Mkdir(targetDir, 0777)
		if err != nil {
			panic(err)
		}
	}

	f, err := os.Create(path.Join(targetDir, fileName))
	if err != nil {
		panic(err)
	}

	return f
}
