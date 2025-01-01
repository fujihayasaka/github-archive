package integration

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"testing"
	"time"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/pkg/errors"
)

type ServerExecution struct {
	api    *exec.Cmd
	cancel context.CancelFunc
	file   *os.File
}

func prefix(x string) string {
	return fmt.Sprintf("--%s", x)
}

func executeWorker(numberOfMessages int, name string, timeTravel bool, timeTravelDate time.Time, logName string, logger *IntegrationLogger, uniqueDatabaseName string, uniqueCollectionName string, usageIngestionQueueName string, zuoraAPIURL string, monolithTwirpServerURL string, printArgs bool) error {
	var (
		timeTravelFlag       string
		timeTravelToDateflag string
	)
	if timeTravel {
		timeTravelFlag = prefix(config.ParameterNameTimeTravel)
		x := timeTravelDate.Format(config.ParameterTimeTravelFormat)
		timeTravelToDateflag = fmt.Sprintf("%s=%s", prefix(config.ParameterNameTimeTravelDate), x)
	}

	var zuoraAPIURLFlag string
	if zuoraAPIURL != "" {
		zuoraAPIURLFlag = fmt.Sprintf("%s=%s", prefix(config.ParameterZuoraApiUrl), zuoraAPIURL)
	}

	var monolithTwirpServerURLFlag string
	if monolithTwirpServerURL != "" {
		monolithTwirpServerURLFlag = fmt.Sprintf("%s=%s", prefix(config.ParameterMonolithTwirpServerURL), monolithTwirpServerURL)
	}

	args := []string{
		prefix(config.ParameterNameRunLimited),
		fmt.Sprintf("%s=%d", prefix(config.ParameterNameNumberOfLimitedMessagesToProcess), numberOfMessages),
		timeTravelFlag,
		timeTravelToDateflag,
		fmt.Sprintf("%s=%s", prefix(config.ParameterNameTestingCollectionName), uniqueCollectionName),
		fmt.Sprintf("%s=%s", prefix(config.ParameterNameTestingDatabaseName), uniqueDatabaseName),
		zuoraAPIURLFlag,
		monolithTwirpServerURLFlag,
	}
	if usageIngestionQueueName != "" {
		args = append(args, fmt.Sprintf("%s=%s", prefix(config.ParameterNameTestingQueueName), usageIngestionQueueName))
	}

	return runCommand(name, args, logName, logger, printArgs)
}

func runCommand(name string, args []string, logName string, logger *IntegrationLogger, printArgs bool) error {
	rootPath := config.RootPath()
	name = filepath.Join(rootPath, name)

	cmd := exec.Command(name, args...)
	cmd.Dir = rootPath

	if printArgs {
		fmt.Printf("Printing command: %s\n", cmd.String())
		fmt.Printf("WARNING: Printing command args will prevent the command from running\n")
		return nil
	}

	logger.Info("Running command", kvp.String("command", fmt.Sprintf("%v", cmd.Args)), kvp.String("dir", cmd.Dir), kvp.String("logName", logName))

	output, outErr := cmd.CombinedOutput()

	file, err := getLogFile(logName)
	if err != nil {
		return err
	}

	defer func() {
		if err := file.Close(); err != nil {
			panic(fmt.Sprintf("error while closing the file. %v", err))
		}
	}()

	if _, err := file.Write([]byte(fmt.Sprintf("%s\n", output))); err != nil {
		return fmt.Errorf("Error writing file %s", err)
	}

	logger.Info(string(output))
	if outErr != nil {
		logger.Error(outErr.Error())
	}
	if outErr != nil {
		return fmt.Errorf("Error running Cmd %s", outErr)
	}

	return nil
}

func aqueductIsRunning() bool {
	port := "18081"

	ln, err := net.Listen("tcp", ":"+port)
	if err != nil {
		return true
	}

	_ = ln.Close()
	return false
}

func runAqueduct() (*exec.Cmd, error) {
	cmd := exec.Command("./script/aqueduct-lite")
	cmd.Dir = "../.."
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	cmdReader, err := cmd.StdoutPipe()
	if err != nil {
		return nil, fmt.Errorf("Error creating StdoutPipe for Cmd %s", err)
	}

	scanner := bufio.NewScanner(cmdReader)
	go func() {
		file, err := getLogFile("aqueduct.log")
		// close the file once program execution complete
		if err != nil {
			panic(fmt.Sprintf("error while opening the file. %v", err))
		}

		defer func() {
			if err := file.Close(); err != nil {
				panic(fmt.Sprintf("error while closing the file. %v", err))
			}
		}()

		for scanner.Scan() {
			if _, err := file.Write([]byte(fmt.Sprintf("%s\n", scanner.Text()))); err != nil {
				panic(fmt.Sprintf("error while writing the file. %v", err))
			}
		}
	}()

	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("Error starting Cmd %s", err)
	}

	var isRunning bool
	for i := 0; i < 30; i++ {
		if isRunning = aqueductIsRunning(); isRunning {
			break
		}

		time.Sleep(2 * time.Second)
	}

	if !isRunning {
		return nil, fmt.Errorf("Error starting aqueduct %s", stderr.String())
	}

	return cmd, nil
}

func serverIsRunning(localServer string) bool {
	cmd := exec.Command("curl", "-s", fmt.Sprintf("%s/_ping", localServer))
	cmd.Dir = "../.."
	out, err := cmd.CombinedOutput()
	if err != nil {
		return false
	}
	return string(out) == "OK -  - DONE"
}

func runServer(uniqueDatabaseName string, uniqueCollectionName string, uniqueQueueName string, port int, localServer string, logger *IntegrationLogger) (*ServerExecution, error) {

	cmdContext, cancel := context.WithCancel(context.Background())
	cmd := exec.CommandContext(cmdContext,
		"./script/api",
		fmt.Sprintf("%s=%s", prefix(config.ParameterNameTestingCollectionName), uniqueCollectionName),
		fmt.Sprintf("%s=%s", prefix(config.ParameterNameTestingDatabaseName), uniqueDatabaseName),
		fmt.Sprintf("%s=%s", prefix(config.ParameterNameTestingQueueName), uniqueQueueName),
	)

	logName := "api.log"
	cmd.Env = append(cmd.Env, fmt.Sprintf("HTTP_PORT=%d", port))
	cmd.Env = append(cmd.Env, "SKIP_HMAC=true")
	cmd.Dir = "../.."

	logger.Info("Running command", kvp.String("command", fmt.Sprintf("%v", cmd.Args)), kvp.String("dir", cmd.Dir), kvp.String("logName", logName))
	file, err := getLogFile(logName)
	if err != nil {
		cancel()
		return nil, fmt.Errorf("error while opening the file. %v", err)
	}

	stdOut, err := cmd.StdoutPipe()
	if err != nil {
		cancel()
		return nil, fmt.Errorf("error creating StdoutPipe for Cmd %s", err)
	}

	writer := func(file *os.File, scanner *bufio.Scanner) {
		for scanner.Scan() {
			if _, err := file.Write([]byte(fmt.Sprintf("%s\n", scanner.Text()))); err != nil {
				logger.WithError(err).Error("error while writing the file")
			}
		}
	}
	scanner := bufio.NewScanner(stdOut)
	go writer(file, scanner)

	stdErr, err := cmd.StderrPipe()
	if err != nil {
		cancel()
		return nil, fmt.Errorf("error creating StdoutPipe for Cmd %s", err)
	}

	errScanner := bufio.NewScanner(stdErr)
	go writer(file, errScanner)

	err = cmd.Start()
	if err != nil {
		cancel()
		return nil, fmt.Errorf("error starting Cmd %s", err)
	}

	for i := 0; i < 20; i++ {
		if serverIsRunning(localServer) {
			logger.Info("==> Server is running")

			return &ServerExecution{
				api:    cmd,
				cancel: cancel,
				file:   file,
			}, nil
		}

		time.Sleep(2 * time.Second)
	}

	cancel()
	return nil, fmt.Errorf("server is not running")
}

func getLogFile(name string) (*os.File, error) {
	fullPathName := filepath.Join(config.RootPath(), "logs", name)
	if err := os.MkdirAll(filepath.Dir(fullPathName), 0770); err != nil {
		return nil, fmt.Errorf("error while creating the directory. %v", err)
	}
	file, err := os.OpenFile(fullPathName, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0777)
	if err != nil {
		return nil, fmt.Errorf("error while opening the file. %v", err)
	}
	return file, nil
}

func build() error {
	cmd := exec.Command("make", "build")
	cmd.Dir = "../.."

	output, err := cmd.CombinedOutput()
	if err != nil {
		return errors.Wrap(err, "error building")
	}

	fmt.Print(string(output))

	return nil
}

func PrepareTesting(m *testing.M) int {
	var queue *exec.Cmd

	if err := build(); err != nil {
		fmt.Println("error building ", err)
		return 1
	}

	if !aqueductIsRunning() {
		x, err := runAqueduct()
		if err != nil {
			fmt.Println(fmt.Sprint(err))
			return 1
		}
		queue = x

		defer func() {
			err := queue.Process.Signal(syscall.SIGTERM)
			if err != nil {
				panic(fmt.Sprintf("error stopping queue %v", err))
			}
		}()
	}
	return m.Run()
}
