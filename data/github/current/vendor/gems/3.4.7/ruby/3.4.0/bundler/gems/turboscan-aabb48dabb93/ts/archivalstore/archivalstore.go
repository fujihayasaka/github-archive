// Package archivalstore provides a SarifStore implementation that can upload and download SARIF files to multiple nodes in an enterprise environment.
package archivalstore

import (
	"bytes"
	"context"
	stderrors "errors" //lint:ignore faillint importing for errors.Join
	"fmt"
	"io"
	"math/rand"
	"net/url"
	"strings"

	"gocloud.dev/blob"

	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"

	"github.com/github/turboscan/ts/config"
	enterprise "github.com/github/turboscan/ts/monolith_twirp/enterprise/v1"
	"github.com/github/turboscan/ts/sarif/store"
	"github.com/hashicorp/go-multierror"
)

// ArchivalStore handles clustered storage on Enterprise by writing to multiple store.SarifStore MinIO nodes.
// In Dotcom and Proxima we rely on Azure to replicate the data and a store.SarifStore is sufficient.
type ArchivalStore interface {
	Archive(ctx context.Context, r io.Reader, archiveDataUrl string) (string, error)
	Download(ctx context.Context, archiveDataUrl string) (*bytes.Buffer, error)
}

type archivalStore struct {
	getStoreFunc func(node string) store.SarifStore
	storageAPI   enterprise.StorageAPI
}

type nullStorageApi struct{}

func (n nullStorageApi) Hosts(ctx context.Context, request *enterprise.HostsRequest) (*enterprise.HostsResponse, error) {
	return &enterprise.HostsResponse{}, nil
}

func NullStorageAPI() enterprise.StorageAPI {
	return nullStorageApi{}
}

func NewArchivalStoreFromConfig(singleStore store.SarifStore, cfg *config.Config) (ArchivalStore, error) {
	// Clustered storage is only supported on Enterprise when using Minio.
	if !cfg.IsEnterpriseEnv() || cfg.GetStorageEngine() != config.STORAGE_S3 {
		return singleStore, nil
	}

	storageAPI, err := cfg.NewEnterpriseStorageAPI()
	if err != nil {
		return nil, err
	}

	getStoreFunc := func(node string) store.SarifStore {
		return store.NewSarifStoreWithOpenFunc(func(ctx context.Context) (*blob.Bucket, error) {
			return store.GetS3Bucket(
				cfg.AWSID,
				cfg.AWSSecret,
				cfg.AWSRegion,
				cfg.S3Bucket,
				fmt.Sprintf("%s://%s:%d", cfg.S3NodeProtocol, node, cfg.S3NodePort),
			)
		}, int64(cfg.MaxSarifSize))
	}

	return NewArchivalStore(getStoreFunc, storageAPI), nil
}

func NewArchivalStore(getStoreFunc func(node string) store.SarifStore, storageAPI enterprise.StorageAPI) ArchivalStore {
	return &archivalStore{
		getStoreFunc: getStoreFunc,
		storageAPI:   storageAPI,
	}
}

func (as *archivalStore) getNodes(ctx context.Context) ([]string, error) {
	response, err := as.storageAPI.Hosts(ctx, &enterprise.HostsRequest{})
	if err != nil {
		return nil, errors.Wrap(err, "could not fetch storage hosts")
	}
	return response.LeastLoaded, nil
}

func (as *archivalStore) Archive(ctx context.Context, r io.Reader, archiveDataUrl string) (string, error) {
	destURL, err := url.Parse(archiveDataUrl)
	if err != nil {
		return "", err
	}

	nodes, err := as.getNodes(ctx)
	if err != nil {
		return "", err
	}

	if len(nodes) == 0 {
		return "", errors.New("no storage nodes available")
	}

	// We read the full content of the file into memory, which is not ideal, but is necessary to support concurrently writing to multiple nodes
	content, err := io.ReadAll(r)
	if err != nil {
		return "", err
	}

	group, ctx := errgroup.WithContext(ctx)
	for _, node := range nodes {
		group.Go(func() error {
			return upload(ctx, as.getStoreFunc(node), destURL.Path, content)
		})
	}

	if waitErr := group.Wait(); waitErr != nil {
		return "", errors.Wrap(waitErr, "failed to archive SARIF")
	}

	return (&url.URL{Host: strings.Join(nodes, ","), Path: destURL.Path}).String(), nil
}

func upload(ctx context.Context, ss store.SarifStore, path string, content []byte) error {
	if err := ss.Open(ctx); err != nil {
		return err
	}
	err := ss.Upload(ctx, bytes.NewReader(content), path)
	return stderrors.Join(err, ss.Close(ctx))
}

func download(ctx context.Context, ss store.SarifStore, path string) (*bytes.Buffer, error) {
	if err := ss.Open(ctx); err != nil {
		return nil, err
	}
	buf, err := ss.Download(ctx, path)
	return buf, stderrors.Join(err, ss.Close(ctx))
}

func (as *archivalStore) Download(ctx context.Context, archiveDataUrl string) (*bytes.Buffer, error) {
	sourceURL, err := url.Parse(archiveDataUrl)
	if err != nil {
		return nil, err
	}

	nodes := strings.Split(sourceURL.Host, ",")

	// Shuffle the nodes to avoid always trying the same node first.
	rand.Shuffle(len(nodes), func(i, j int) {
		nodes[i], nodes[j] = nodes[j], nodes[i]
	})

	var errs *multierror.Error
	for _, node := range nodes {
		ss := as.getStoreFunc(node)
		r, err := download(ctx, ss, sourceURL.Path)
		if err == nil {
			return r, nil
		}
		errs = multierror.Append(errs, err)
	}

	return nil, errs
}
