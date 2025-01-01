package chatops

import (
	"crypto/rsa"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"net/url"
	"strings"
)

// Handler implements HTTP handlers to respond to Chatops RPC requests.
type Handler struct {
	ns   *Namespace
	bots []*rsa.PublicKey
	uri  *url.URL
	path string
}

type mux interface {
	Handle(string, http.Handler)
}

// NewHandler initializes a Handler from a given Namespace and url prefix. The
// prefix must include the URI scheme/host for Chatops RPC Signature
// verification.
func NewHandler(ns *Namespace, prefix string) (*Handler, error) {
	uri, err := url.Parse(prefix)
	if err != nil {
		return nil, err
	}
	if uri.Host == "" {
		return nil, fmt.Errorf("prefix must be a full url: 'https://{host}/{path}'")
	}

	return &Handler{
		ns:   ns,
		uri:  uri, // keeps http scheme+host for server
		path: strings.TrimSuffix(uri.Path, "/") + "/_chatops",
	}, nil
}

// AddBot adds the rsa public key for a bot to a handler.
func (h *Handler) AddBot(key *rsa.PublicKey) {
	h.bots = append(h.bots, key)
}

// Setup routes this Handler through the given http multiplexer.
func (h *Handler) Setup(srv mux) {
	srv.Handle(h.path+"/", h)
	srv.Handle(h.path, h)
}

// ServeHTTP satisfies the http.Handler interface and is the entry point for
// HTTP requests.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	body, err := ioutil.ReadAll(io.LimitReader(r.Body, 1048576))
	_ = r.Body.Close()
	if err != nil {
		sendJSON(w, 400, &CommandResponse{
			Result: err.Error(),
		})
		return
	}

	if err := h.verifySignature(r, string(body)); err != nil {
		sendJSON(w, 403, &CommandResponse{
			Result: err.Error(),
		})
		return
	}

	switch r.Method {
	case http.MethodPost:
		req := &CommandRequest{}
		if err := json.Unmarshal(body, req); err != nil {
			sendJSON(w, 400, &CommandResponse{
				Result: fmt.Sprintf("Error parsing chatops Command Request: %s", err),
			})
			return
		}

		m, err := h.ns.Method(req.Method)
		if err != nil {
			sendJSON(w, 404, &CommandResponse{
				Result: fmt.Sprintf("No chatops method: %q", req.Method),
			})
			return
		}

		res, err := m.Do(r.Context(), req)
		if err != nil {
			sendJSON(w, 500, &CommandResponse{
				Result: fmt.Sprintf("Error: %s", err),
			})
			return
		}
		sendJSON(w, 200, res)
	case http.MethodGet, http.MethodHead:
		sendJSON(w, 200, h.list())
	default:
		list := h.list()
		list.ErrorResponse = fmt.Sprintf("Invalid HTTP method: %q", r.Method)
		sendJSON(w, 405, list)
	}
}

func (h *Handler) list() *ListResponse {
	return &ListResponse{
		Namespace: h.ns.Name,
		Help:      h.ns.Help,
		Version:   3,
		Methods:   h.ns.Methods(),
	}
}

func (h *Handler) verifySignature(r *http.Request, body string) error {
	sig, err := SignatureHeader(r)
	if err != nil {
		return err
	}

	for _, key := range h.bots {
		u := *h.uri // merge scheme/host with req path
		u.Path = r.URL.Path
		if err := Verify(key, URLHeaderSignatureInput(&u, r.Header, body), sig.Signature); err == nil {
			return nil
		}
	}
	return errors.New("chatops Signature does not match")
}

func sendJSON(w http.ResponseWriter, status int, obj interface{}) {
	by, err := json.Marshal(obj)
	if err != nil {
		http.Error(w, "Error encoding response json: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(by)
}
