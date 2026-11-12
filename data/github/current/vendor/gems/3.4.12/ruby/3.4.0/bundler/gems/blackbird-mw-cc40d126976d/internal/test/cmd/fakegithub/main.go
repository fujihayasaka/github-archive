package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"

	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/test/fakegithub"
	"github.com/github/blackbird-mw/internal/types"
)

const port = 11223

func main() {
	fmt.Println("Hello, this is fake GitHub!")

	db := fakegithub.NewGitHubDb()

	mux := chi.NewMux()
	mux.Use(middleware.Logger)
	mux.Use(middleware.Recoverer)
	mux.Get("/ping", func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte("pong\n")) })
	mux.Get("/reset", func(w http.ResponseWriter, r *http.Request) {
		db.Reset()
		w.WriteHeader(http.StatusNoContent)
	})
	mux.Post("/internal/blackbird/accessible_resources", func(w http.ResponseWriter, r *http.Request) {

		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "Failed to read request body", http.StatusInternalServerError)
			return
		}
		defer r.Body.Close()

		var data AccessibleResourcesRequest
		err = json.Unmarshal(body, &data)
		if err != nil {
			http.Error(w, "Failed to unmarshal JSON", http.StatusBadRequest)
			return
		}

		ar := &entities.AccessibleResources{
			AccessiblePrivateRepoIds:  []uint64{},
			AccessibleOwnerIds:        []uint64{},
			AuthorizedOrganizationIds: []uint64{},
			ProtectedOrganizationIds:  []uint64{},
		}

		for _, repo := range db.ListRepos() {
			if !repo.Public && data.Token == fakegithub.AllAccessToken {
				ar.AccessiblePrivateRepoIds = append(ar.AccessiblePrivateRepoIds, uint64(repo.ID))
			}
		}

		out, err := json.Marshal(ar)
		if err != nil {
			http.Error(w, fmt.Sprintf("Could not marshal JSON for accessible resources: %+v", err), 500)
			return
		}

		w.WriteHeader(200)
		w.Header().Add("Content-Type", "application/json")
		_, err = w.Write(out)
		if err != nil {
			panic(fmt.Sprintf("fatal error serializing JSON: %+v", err))
		}
	})
	mux.Get("/internal/blackbird/repositories/{owner}/{name}", func(w http.ResponseWriter, r *http.Request) {
		owner := chi.URLParam(r, "owner")
		name := chi.URLParam(r, "name")
		repo, ok := db.GetRepoByNWO(types.NWOFromString(fmt.Sprintf("%s/%s", owner, name)))
		if !ok {
			http.Error(w, fmt.Sprintf("Repo %s/%s not found", owner, name), 404)
			return
		}
		writeRepository(w, repo)
	})
	mux.Get("/internal/blackbird/repositories/{id}", func(w http.ResponseWriter, r *http.Request) {
		id := chi.URLParam(r, "id")
		repoID, err := strconv.ParseUint(id, 10, 32)
		if err != nil {
			http.Error(w, fmt.Sprintf("Invalid repo id %s", id), 400)
			return
		}
		repo, ok := db.GetRepoByID(types.RepoID(repoID))
		if !ok {
			http.Error(w, fmt.Sprintf("Repo %s not found", id), 404)
			return
		}
		writeRepository(w, repo)
	})
	mux.Post("/internal/blackbird/repositories", func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, fmt.Sprintf("Could not read request body: %+v", err), 500)
			return
		}
		defer r.Body.Close()

		var repo github.Repository
		err = json.Unmarshal(body, &repo)
		if err != nil {
			http.Error(w, fmt.Sprintf("Could not unmarshal JSON: %+v", err), 400)
			return
		}
		db.AddRepository(repo)
		w.WriteHeader(http.StatusCreated)
	})
	mux.Put("/internal/blackbird/repositories/{id}", func(w http.ResponseWriter, r *http.Request) {
		id := chi.URLParam(r, "id")
		repoID, err := strconv.ParseUint(id, 10, 32)
		if err != nil {
			http.Error(w, fmt.Sprintf("Invalid repo id %s", id), 400)
			return
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, fmt.Sprintf("Could not read request body: %+v", err), 500)
			return
		}
		defer r.Body.Close()

		var repo github.Repository
		err = json.Unmarshal(body, &repo)
		if err != nil {
			http.Error(w, fmt.Sprintf("Could not unmarshal JSON: %+v", err), 400)
			return
		}
		err = db.UpdateRepository(types.RepoID(repoID), repo)
		if err != nil {
			http.Error(w, "failed to update repository", 500)
			return
		}
	})
	mux.Delete("/internal/blackbird/repositories/{id}", func(w http.ResponseWriter, r *http.Request) {
		id := chi.URLParam(r, "id")
		repoID, err := strconv.ParseUint(id, 10, 32)
		if err != nil {
			http.Error(w, fmt.Sprintf("Invalid repo id %s", id), 400)
			return
		}
		db.DeleteRepository(types.RepoID(repoID))
		w.WriteHeader(http.StatusNoContent)
	})

	err := http.ListenAndServe(fmt.Sprintf(":%d", port), mux)
	if err != nil {
		fmt.Println(err)
	}

	fmt.Println("Shutting down...")
}

func writeRepository(w http.ResponseWriter, repo *github.Repository) {
	out, err := json.Marshal(repo)
	if err != nil {
		http.Error(w, fmt.Sprintf("Could not marshal JSON for repo %d: %+v", repo.ID, err), 500)
		return
	}

	w.WriteHeader(200)
	w.Header().Add("Content-Type", "application/json")
	_, err = w.Write(out)
	if err != nil {
		panic(fmt.Errorf("fatal error serializing JSON: %+v", err))
	}
}

// TODO: Copied from the auth package because depending on that package brings in a dependency on the clibs which
// dramatically complicates the fake github server.
type AccessibleResourcesResponse struct {
	AccessibleRepositoryIDs     []int64 `json:"accessible_repository_ids"`
	AuthorizedOrganizationIDs   []int64 `json:"authorized_organization_ids"`
	ProtectedOrganizationIDs    []int64 `json:"protected_organization_ids"`
	OutsideCollaboratorOwnerIDs []int64 `json:"outside_collaborator_owner_ids"`
}

type AccessibleResourcesRequest struct {
	ActorID                     uint32 `json:"actor_id"`
	KeyPrefix                   string `json:"key_prefix"`
	RequestUserIP               string `json:"request_user_ip"`
	SessionID                   string `json:"session_id"`
	Token                       string `json:"token"`
	TokenKind                   string `json:"token_kind"`
	ForceNewAccessibleResources bool   `json:"force_new_accessible_resources"`
}
