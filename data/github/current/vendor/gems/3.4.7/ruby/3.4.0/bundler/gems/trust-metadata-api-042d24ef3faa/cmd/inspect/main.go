// this cli tool accepts json files as an argument, parses them into a struct

package main

import (
	"context"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"reflect"
	"strings"

	"github.com/github/trust-metadata-api/pkg/attestation"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/spf13/cobra"
	"google.golang.org/protobuf/encoding/protojson"
)

var versionFlagged bool
var dumpCerts bool
var GitCommit = "unknown"
var logo = `
   _                       __ 
  (_)__  ___ ___  ___ ____/ /_
 / / _ \(_-</ _ \/ -_) __/ __/
/_/_//_/___/ .__/\__/\__/\__/ 
          /_/                 
`

func main() {
	// setup cobra to parse cli options
	rootCmd := &cobra.Command{
		Use:   "inspect bundle.json",
		Short: "inspect a sigstore bundle",
		Long:  "inspect a sigstore bundle",
		Run:   inspectFile,
	}

	rootCmd.Flags().BoolVar(&versionFlagged, "version", false, "Prints version information")
	rootCmd.Flags().BoolVar(&dumpCerts, "dump-certs", false, "Dumps certs")

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func inspectFile(cmd *cobra.Command, args []string) {
	if versionFlagged {
		fmt.Printf("Version %s\n", GitCommit)
		return
	}

	if len(args) == 0 {
		fmt.Println("no argument provided")
		_ = cmd.Usage()

		return
	}

	fmt.Printf("%s\n", logo)
	fileName := args[0]
	fmt.Printf("Parsing %s…\n", fileName)

	data, err := os.ReadFile(fileName)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	var inputJSON map[string]json.RawMessage
	err = json.Unmarshal(data, &inputJSON)

	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	var bundleData []byte
	var protoBundle protobundle.Bundle

	if _, ok := inputJSON["bundle"]; ok {
		bundleData = inputJSON["bundle"]
	} else {
		bundleData = data
	}

	err = protojson.Unmarshal(bundleData, &protoBundle)

	if err != nil {
		fmt.Printf("oh no error %s\n", err)
		os.Exit(1)
	}

	fmt.Println()
	fmt.Printf("Bundle: %s\n", protoBundle.MediaType)

	bundle, err := sgbundle.NewBundle(&protoBundle)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	verificationContent, err := bundle.VerificationContent()
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	cert := verificationContent.Certificate()
	if cert == nil {
		fmt.Println("bundle does not contain a certificate")
		os.Exit(1)
	}

	if dumpCerts {
		fmt.Printf("Certificate:\n------------\n")
		printReflectedFields(cert)
		fmt.Println()
	}

	ctx := context.Background()

	fmt.Printf("Provenance Summary:\n-------------------\n")
	ps, err := attestation.NewProvenanceSummary(ctx, bundle)
	if err != nil {
		fmt.Printf("oh no provenance summary error %s\n", err)
		os.Exit(1)
	}

	printReflectedFields(ps)
	fmt.Println()

	envelope, err := bundle.Envelope()
	if err != nil {
		fmt.Printf("could not retrieve envelope: %s\n", err)
		os.Exit(1)
	}
	statement, err := envelope.Statement()
	if err != nil {
		fmt.Printf("could not retrieve statement: %s\n", err)
		os.Exit(1)
	}

	fmt.Println("Statement:\n----------")
	fmt.Printf("Type: %s\n", statement.Type)
	fmt.Println()

	fmt.Println("Subjects:\n---------")
	err = PrettyPrint(statement.Subject)
	if err != nil {
		fmt.Printf("oh no pretty print error %s\n", err)
		os.Exit(1)
	}

	fmt.Println()

	fmt.Println("Predicate:\n----------")
	fmt.Printf("Type: %s\n", statement.PredicateType)
	err = PrettyPrint(statement.Predicate)
	if err != nil {
		fmt.Printf("oh no pretty print error %s\n", err)
		os.Exit(1)
	}

	os.Exit(0)
	return
}

func printReflectedFields(s any) {
	visFields := reflect.VisibleFields(reflect.TypeOf(s))
	reflectedValue := reflect.ValueOf(s)

	for _, field := range visFields {
		// skip if field name begins with "Raw"
		// this is cheating slightly but often just adds noise
		if strings.HasPrefix(field.Name, "Raw") {
			continue
		}

		if !field.IsExported() {
			continue
		}

		fieldValue := reflectedValue.FieldByIndex(field.Index)
		valueInterface := fieldValue.Interface()
		switch value := valueInterface.(type) {
		case []byte:
			fmt.Printf("%-30s\t\t %s (%s)\n", field.Name+":", hex.EncodeToString(value), field.Type)
		case []pkix.Extension:
			fmt.Printf("%-30s\t\t(%s)\n", field.Name+":", field.Type)
			for _, ext := range value {
				var derValue string
				if err := attestation.ParseDERString(ext.Value, &derValue); err != nil {
					fmt.Printf("\t%s c=%v:\t %s\n", ext.Id, ext.Critical, string(ext.Value))
				} else {
					fmt.Printf("\t%s c=%v:\t %s (DER)\n", ext.Id, ext.Critical, derValue)
				}
			}
		default:
			fmt.Printf("%-30s\t\t %s (%s)\n", field.Name+":", valueInterface, field.Type)
		}
	}
}

func PrettyPrint(v interface{}) (err error) {
	b, err := json.MarshalIndent(v, "", "  ")

	if err == nil {
		fmt.Println(string(b))
		return nil
	}
	return err
}
