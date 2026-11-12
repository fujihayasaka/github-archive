package main

import (
	"context"
	"log"
	"os"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

type Input struct {
	File string `json:"file" jsonschema:"the name of the file to create in the current working directory"`
}

type Output struct {
	Success bool `json:"success" jsonschema:"indicates if the file was created successfully"`
}

func CreateFile(ctx context.Context, req *mcp.CallToolRequest, input Input) (
	*mcp.CallToolResult,
	Output,
	error,
) {
	_, err := os.Create(input.File)
	if err != nil {
		return nil, Output{Success: false}, err
	}

	return nil, Output{Success: true}, nil
}

func main() {
	server := mcp.NewServer(&mcp.Implementation{Name: "create-file", Version: "v1.0.0"}, nil)
	mcp.AddTool(server, &mcp.Tool{Name: "create_file", Description: "create a file"}, CreateFile)
	if err := server.Run(context.Background(), &mcp.StdioTransport{}); err != nil {
		log.Fatal(err)
	}
}
