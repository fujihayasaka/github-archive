// Package main is the main package for a tool to inspect and debug the DAG.
package main

import (
	"bytes"
	"context"
	"embed"
	"encoding/json"
	"fmt"
	"html/template"
	"image"
	"image/png"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/go-redis/redis/v8"
	"github.com/goccy/go-graphviz"
	"github.com/goccy/go-graphviz/cgraph"
	"github.com/spf13/cobra"
)

var (
	root = &cobra.Command{
		Long:  "inspectordagger",
		RunE:  run,
		Short: "inspectordagger",
		Use:   "inspectordagger",
	}

	//go:embed script/*.lua template/*.html
	fs embed.FS
)

type (
	dag struct {
		Eligible     []string            `json:"eligible_nodes"`
		Dependencies map[string]int      `json:"dependencies"`
		Dependants   map[string][]string `json:"dependants"`
	}

	pageData struct {
		Title string
		Depth string
	}

	nodeSet  map[string]struct{}
	nodeDeps map[string]nodeSet
)

const (
	dumpPath          = "script/dump.lua"
	indexTemplatePath = "template/index.html"
)

//nolint:gochecknoinits // Using an `init` function to add flags is standard for spf13/cobra
func init() {
	root.PersistentFlags().String("redis-addr", "0.0.0.0:6379", "the ip:port that the daemon will listen on")
	root.PersistentFlags().String("namespace", "default", "namespace to use in DAG storage")
	root.PersistentFlags().Int("http-port", 0, "http-port to use for the inspector results")
}

func main() {
	if err := root.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

func run(cmd *cobra.Command, args []string) error {
	telemetryProvider, err := telemetry.NewFromEnv()
	if err != nil {
		return err
	}
	logger := telemetryProvider.Logger.Named("inspectordagger")

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	redisAddr, err := cmd.Flags().GetString("redis-addr")
	if err != nil {
		logger.WithError(err).Error("could not get the value of the redis-addr flag")
		return fmt.Errorf("could not get the value of the redis-addr flag")
	}

	namespace, err := cmd.Flags().GetString("namespace")
	if err != nil {
		logger.WithError(err).Error("could not get the value of the namespace flag")
		return fmt.Errorf("could not get the value of the namespace flag")
	}

	port, err := cmd.Flags().GetInt("http-port")
	if err != nil {
		logger.WithError(err).Error("could not get the value of the http-port flag")
		return fmt.Errorf("could not get the value of the http-port flag")
	}

	// Start the HTTP server in a goroutine
	go func() {
		listener, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
		if err != nil {
			logger.WithError(err).Error("failed to start http server")
			return
		}

		tcpAddr, ok := listener.Addr().(*net.TCPAddr)
		if !ok {
			logger.Error("failed to retrieve the allocated port")
			return
		}
		fmt.Printf("find the graph at http://0.0.0.0:%d?depth=3\n", tcpAddr.Port)

		http.HandleFunc("/", serveHTML)
		http.HandleFunc("/image", serveImage(ctx, redisAddr, namespace, logger))
		server := &http.Server{ReadTimeout: 5 * time.Second}
		err = server.Serve(listener)
		if err != nil {
			logger.WithError(err).Error("failed to start http server")
			return
		}
	}()

	// Create a channel to listen for interrupt or terminate signals from the OS.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	// Wait for a stop signal
	select {
	case <-ctx.Done():
	case <-stop:
	}
	cancel()

	logger.Info("exiting...")
	return nil
}

// drawGraph draws the graph using the given nodes and its dependencies
func drawGraph(ctx context.Context, nodes nodeDeps) (image.Image, error) {
	g, err := graphviz.New(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize graph: %w", err)
	}
	graph, err := g.Graph()
	if err != nil {
		return nil, fmt.Errorf("failed to create graph: %w", err)
	}

	gvNodes := make(map[string]*cgraph.Node)
	for node := range nodes {
		_, ok := gvNodes[node]
		if !ok {
			gvNodes[node], err = graph.CreateNodeByName(node)
			if err != nil {
				return nil, fmt.Errorf("failed to create node: %w", err)
			}
		}
		for dep := range nodes[node] {
			_, ok := gvNodes[dep]
			if !ok {
				gvNodes[dep], err = graph.CreateNodeByName(dep)
				if err != nil {
					return nil, fmt.Errorf("failed to create node: %w", err)
				}
			}
			name := fmt.Sprintf("%s-%s", node, dep)
			_, err = graph.CreateEdgeByName(name, gvNodes[node], gvNodes[dep])
			if err != nil {
				return nil, fmt.Errorf("failed to create edge: %w", err)
			}
		}
	}
	img, err := g.RenderImage(ctx, graph)
	if err != nil {
		return nil, fmt.Errorf("failed to render graph: %w", err)
	}
	return img, nil
}

// traverseGraph traverses the graph to find the nodes and their dependencies
func traverseGraph(ctx context.Context, d *dag, namespace string, depth int) (nodeDeps, error) {
	depsPerNode := make(nodeDeps)
	processed := make(nodeSet)
	var currDepth int
	eligible := d.Eligible
	for currDepth < depth && len(eligible) > 0 && ctx.Err() == nil {
		var newEligible []string
		for _, node := range eligible {
			d.Dependencies[namespace+":"+node+":dependencies"] = 0
			processed[node] = struct{}{}
			for _, dependant := range d.Dependants[namespace+":"+node+":dependants"] {
				if _, ok := depsPerNode[node]; !ok {
					depsPerNode[node] = make(nodeSet)
				}
				depsPerNode[node][dependant] = struct{}{}
				if d.Dependencies[namespace+":"+dependant+":dependencies"] == 1 {
					newEligible = append(newEligible, dependant)
				} else {
					d.Dependencies[namespace+":"+dependant+":dependencies"]--
				}
			}
		}
		currDepth++
		eligible = newEligible
	}
	for k := range depsPerNode {
		if _, ok := processed[k]; !ok {
			delete(depsPerNode, k)
		}
	}
	return depsPerNode, nil
}

// fetchGraph fetches the graph from Redis
func fetchGraph(ctx context.Context, addr, namespace string) (*dag, error) {
	// Create redis client
	opts := &redis.Options{
		Addr:     addr, // Redis server address
		Password: "",   // No password set
		DB:       0,    // Use default DB
	}

	// Create a new Redis client.
	c := redis.NewClient(opts)

	// Read the dump lua script
	dump, err := fs.ReadFile(dumpPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read dump lua script: %w", err)
	}

	// Fetch the graph from Redis in JSON format
	o, err := c.Eval(ctx, string(dump), []string{namespace}).Result()
	if err != nil {
		return nil, fmt.Errorf("failed to fetch graph: %w", err)
	}

	// Unmarshal the JSON graph
	jsonResp, ok := o.(string)
	if !ok {
		return nil, fmt.Errorf("failed to convert graph to string")
	}
	var d dag
	if err := json.Unmarshal([]byte(jsonResp), &d); err != nil {
		return nil, fmt.Errorf("failed to unmarshal graph: %w", err)
	}
	return &d, nil
}

// serveImage returns a handler that serves the given image.
func serveImage(ctx context.Context, redisAddr, namespace string, logger log.Logger) func(http.ResponseWriter, *http.Request) {
	return func(w http.ResponseWriter, r *http.Request) {
		depth := r.URL.Query().Get("depth")
		if depth == "" {
			depth = "3"
		}
		maxDepth, err := strconv.Atoi(depth)
		if err != nil {
			logger.WithError(err).Error("failed to convert depth to int")
			http.Error(w, "failed to convert depth to int", http.StatusInternalServerError)
			return
		}
		if maxDepth < 1 {
			logger.Error("depth must be greater than 0")
			http.Error(w, "depth must be greater than 0", http.StatusInternalServerError)
			return
		}
		d, err := fetchGraph(ctx, redisAddr, namespace)
		if err != nil {
			logger.WithError(err).Error("failed to fetch graph from Redis")
			http.Error(w, "failed to fetch graph from Redis", http.StatusInternalServerError)
			return
		}

		nodes, err := traverseGraph(ctx, d, namespace, maxDepth)
		if err != nil {
			logger.WithError(err).Error("failed to traverse graph")
			http.Error(w, "failed to traverse graph", http.StatusInternalServerError)
			return
		}
		img, err := drawGraph(ctx, nodes)
		if err != nil {
			logger.WithError(err).Error("failed to draw graph")
			return
		}
		var buf bytes.Buffer
		if err = png.Encode(&buf, img); err != nil {
			logger.WithError(err).Error("failed to encode image")
			return
		}
		w.Header().Set("Content-Type", "image/png")
		_, _ = w.Write(buf.Bytes())
	}
}

// serveHTML returns a handler that serves the given HTML to show the DAG image.
func serveHTML(w http.ResponseWriter, r *http.Request) {
	data := pageData{
		Title: "Inspector DAGger",
		Depth: r.URL.Query().Get("depth"),
	}

	tmpl, err := template.ParseFS(fs, indexTemplatePath)
	if err != nil {
		http.Error(w, "Failed to load template", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/html")

	err = tmpl.Execute(w, data)
	if err != nil {
		http.Error(w, "Failed to render page", http.StatusInternalServerError)
		return
	}
}
