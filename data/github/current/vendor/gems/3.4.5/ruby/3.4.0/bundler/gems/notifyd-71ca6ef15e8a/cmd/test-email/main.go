// test-email is a small HTTP server that renders a HTML template
// meant specifically to test email layouts.
// At the moment we use views.HTMLEmailView to supply the template with data.
//
// Run the application by running: `go run cmd/test-email/main.go`
// You can change the port (default: 8090) by setting the `--port` flag
package main

import (
	"flag"
	"html/template"
	"log"
	"net/http"
	"time"

	"github.com/github/notifyd/internal/email/layout/views"
)

var port string

func main() {
	flag.StringVar(&port, "port", "8090", "port that the HTTP server runs on")
	flag.Parse()

	// notification/email view/message to be sent
	emailView := new(views.HTMLEmailView)
	emailView.Subject = "Re: #843 [Email polish] Revisit design of primer styled emails"
	emailView.Body = "<p>Welcome to the world</p><p>Please check <strong>the link</strong> below</p>"
	emailView.URL = "https://github.com/github/notifyd/issues/843"
	emailView.UnsubscribeURL = "https://github.com/github/notifyd/issues/843/unsubscribe"
	emailView.Reason = "you were mentioned"

	// set up http server
	http.HandleFunc("/", func(w http.ResponseWriter, req *http.Request) {
		// load layout, on every call for testing
		tpl, err := template.New("simple").ParseFiles("internal/email/layout/views/templates/simple_layout.html")
		if err != nil {
			log.Fatalf("failed to load layout: %v", err)
		}

		// write output to browser
		if err := tpl.Execute(w, emailView); err != nil {
			log.Printf("failed to execute template: %v", err)
			http.Error(w, err.Error(), http.StatusInternalServerError)
		}
	})

	// time to run the server
	log.Println("Setting up email preview server at localhost:" + port)
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           nil,
		ReadHeaderTimeout: 2 * time.Second,
	}
	if err := srv.ListenAndServe(); err != nil {
		log.Panicf("failed to start http server: %v", err)
	}
}
