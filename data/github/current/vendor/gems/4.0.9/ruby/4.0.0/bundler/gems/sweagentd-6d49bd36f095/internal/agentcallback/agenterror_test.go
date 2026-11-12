package agentcallback

import (
	"encoding/json"
	"testing"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRollupCheck(t *testing.T) {
	testCases := []struct {
		name   string
		err    *AgentError
		rollup string
	}{
		{
			name: "error is AgentError that implements Class",
			err: &AgentError{
				Name: "SomeError",
				Code: ErrorCode{
					StringValue: "some_error_code",
					IsString:    true,
				},
				Text: "Some error content",
			},
			rollup: "AgentError: SomeError (some_error_code)",
		},
		{
			name: "error is AgentError with no specific identifier",
			err: &AgentError{
				Text: "Some error content",
			},
			rollup: "AgentError: Error",
		},
	}

	for _, tt := range testCases {
		t.Run(tt.name, func(t *testing.T) {
			require.Equal(t, tt.rollup, tt.err.RollupInfo())
		})
	}
}

func TestAgentError_Unmarshal(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected AgentError
	}{
		{
			name: "CAPIError with 408 timeout - no code field",
			input: `{
				"ghRequestId": "1C01:3861F2:2B918D:46F0A8:68E1A098",
				"isVisionFlow": false,
				"message": "408 408 Request Timeout",
				"name": "CAPIError",
				"request_id": "00000-18e6e0c9-797e-4fa2-97d0-74efa13eb727",
				"skipReport": false,
				"stack": "CAPIError: 408 408 Request Timeout\n\n at Function.CAPIError (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts:281:16)",
				"text": "408 408 Request Timeout"
			}`,
			expected: AgentError{
				Code:    ErrorCode{},
				Name:    "CAPIError",
				Text:    "408 408 Request Timeout",
				Message: "408 408 Request Timeout",
				Stack:   "CAPIError: 408 408 Request Timeout\n\n at Function.CAPIError (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts:281:16)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "Function.CAPIError",
						FileName:   "/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts",
						LineNumber: 281,
					},
				},
				RequestID:       "00000-18e6e0c9-797e-4fa2-97d0-74efa13eb727",
				GitHubRequestID: "1C01:3861F2:2B918D:46F0A8:68E1A098",
				SkipReport:      false,
				IsVisionFlow:    false,
			},
		},
		{
			name: "CAPIError with 413 - no code field",
			input: `{
				"ghRequestId": "8C11:1EE3F4:202BE:337FC:68E0C333",
				"isVisionFlow": false,
				"message": "413 413 Request Entity Too Large",
				"name": "CAPIError",
				"request_id": "00000-0db44cb3-4215-49b6-9603-94256d2bd17c",
				"skipReport": false,
				"stack": "CAPIError: 413 413 Request Entity Too Large\n\n at Function.CAPIError (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts:281:16)",
				"text": "413 413 Request Entity Too Large"
			}`,
			expected: AgentError{
				Code:    ErrorCode{},
				Name:    "CAPIError",
				Text:    "413 413 Request Entity Too Large",
				Message: "413 413 Request Entity Too Large",
				Stack:   "CAPIError: 413 413 Request Entity Too Large\n\n at Function.CAPIError (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts:281:16)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "Function.CAPIError",
						FileName:   "/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts",
						LineNumber: 281,
					},
				},
				RequestID:       "00000-0db44cb3-4215-49b6-9603-94256d2bd17c",
				GitHubRequestID: "8C11:1EE3F4:202BE:337FC:68E0C333",
				SkipReport:      false,
				IsVisionFlow:    false,
			},
		},
		{
			name: "CAPIError with request timeout - no request_id or ghRequestId",
			input: `{
				"isVisionFlow": false,
				"message": "Request timed out.",
				"name": "CAPIError",
				"skipReport": false,
				"stack": "CAPIError: Request timed out.\n at Function.CAPIError (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts:281:16)",
				"text": "Request timed out."
			}`,
			expected: AgentError{
				Code:    ErrorCode{},
				Name:    "CAPIError",
				Text:    "Request timed out.",
				Message: "Request timed out.",
				Stack:   "CAPIError: Request timed out.\n at Function.CAPIError (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts:281:16)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "Function.CAPIError",
						FileName:   "/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts",
						LineNumber: 281,
					},
				},
				SkipReport:   false,
				IsVisionFlow: false,
			},
		},
		{
			name: "CAPIError with string code - quota_exceeded",
			input: `{
				"code": "quota_exceeded",
				"ghRequestId": "F802:3A1FC7:1CC3708:22CAE3D:68E3BF76",
				"isVisionFlow": false,
				"message": "402 You have no quota",
				"name": "CAPIError",
				"request_id": "00000-f618f4f3-3f76-4e33-8a3a-5d1659218c41",
				"skipReport": false,
				"stack": "CAPIError: 402 You have no quota\n at Function.CAPIError (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts:281:16)",
				"text": "402 You have no quota"
			}`,
			expected: AgentError{
				Code: ErrorCode{
					StringValue: "quota_exceeded",
					IsString:    true,
				},
				Name:    "CAPIError",
				Text:    "402 You have no quota",
				Message: "402 You have no quota",
				Stack:   "CAPIError: 402 You have no quota\n at Function.CAPIError (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts:281:16)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "Function.CAPIError",
						FileName:   "/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts",
						LineNumber: 281,
					},
				},
				RequestID:       "00000-f618f4f3-3f76-4e33-8a3a-5d1659218c41",
				GitHubRequestID: "F802:3A1FC7:1CC3708:22CAE3D:68E3BF76",
				SkipReport:      false,
				IsVisionFlow:    false,
			},
		},
		{
			name: "Generic Error - branch does not exist",
			input: `{
				"isVisionFlow": false,
				"message": "Branch copilot/fix-54e96664-cb0a-4d4d-91b1-8a46f2a862ca does not exist in repo colby/someCoolRepo and no base commit was provided.",
				"name": "Error",
				"skipReport": false,
				"stack": "Error: Branch copilot/fix-54e96664-cb0a-4d4d-91b1-8a46f2a862ca does not exist in repo colby/someCoolRepo and no base commit was provided.\n at Ly.cloneRepo (/home/runner/work/_temp/copilot-developer-action-main/src/runner/git/default.ts:215:23)",
				"text": "Branch copilot/fix-54e96664-cb0a-4d4d-91b1-8a46f2a862ca does not exist in repo colby/someCoolRepo and no base commit was provided."
			}`,
			expected: AgentError{
				Code:    ErrorCode{},
				Name:    "Error",
				Text:    "Branch copilot/fix-54e96664-cb0a-4d4d-91b1-8a46f2a862ca does not exist in repo colby/someCoolRepo and no base commit was provided.",
				Message: "Branch copilot/fix-54e96664-cb0a-4d4d-91b1-8a46f2a862ca does not exist in repo colby/someCoolRepo and no base commit was provided.",
				Stack:   "Error: Branch copilot/fix-54e96664-cb0a-4d4d-91b1-8a46f2a862ca does not exist in repo colby/someCoolRepo and no base commit was provided.\n at Ly.cloneRepo (/home/runner/work/_temp/copilot-developer-action-main/src/runner/git/default.ts:215:23)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "Ly.cloneRepo",
						FileName:   "/home/runner/work/_temp/copilot-developer-action-main/src/runner/git/default.ts",
						LineNumber: 215,
					},
				},
				SkipReport:   false,
				IsVisionFlow: false,
			},
		},
		{
			name: "TypeError - unsupported file type",
			input: `{
				"isVisionFlow": false,
				"message": "unsupported file type: undefined",
				"name": "TypeError",
				"skipReport": false,
				"stack": "TypeError: unsupported file type: undefined\n at imageSize (/home/runner/work/_temp/copilot-developer-action-main/node_modules/image-size/dist/index.mjs:985:9)",
				"text": "unsupported file type: undefined"
			}`,
			expected: AgentError{
				Code:    ErrorCode{},
				Name:    "TypeError",
				Text:    "unsupported file type: undefined",
				Message: "unsupported file type: undefined",
				Stack:   "TypeError: unsupported file type: undefined\n at imageSize (/home/runner/work/_temp/copilot-developer-action-main/node_modules/image-size/dist/index.mjs:985:9)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "imageSize",
						FileName:   "/home/runner/work/_temp/copilot-developer-action-main/node_modules/image-size/dist/index.mjs",
						LineNumber: 985,
					},
				},
				SkipReport:   false,
				IsVisionFlow: false,
			},
		},
		{
			name: "CAPIError with string code - rate_limited",
			input: `{
				"code": "rate_limited",
				"ghRequestId": "603B:22671E:49533C:638A05:68E48CE4",
				"isVisionFlow": false,
				"message": "429 Sorry, you have exceeded your Copilot token usage.",
				"name": "CAPIError",
				"request_id": "00000-25c1943e-61c0-49de-93b5-cd1bf1f4020f",
				"skipReport": false,
				"stack": "CAPIError: 429 Sorry, you have exceeded your Copilot token usage.\n at Function.fromAPIError (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts:281:16)",
				"text": "429 Sorry, you have exceeded your Copilot token usage."
			}`,
			expected: AgentError{
				Code: ErrorCode{
					StringValue: "rate_limited",
					IsString:    true,
				},
				Name:    "CAPIError",
				Text:    "429 Sorry, you have exceeded your Copilot token usage.",
				Message: "429 Sorry, you have exceeded your Copilot token usage.",
				Stack:   "CAPIError: 429 Sorry, you have exceeded your Copilot token usage.\n at Function.fromAPIError (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts:281:16)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "Function.fromAPIError",
						FileName:   "/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts",
						LineNumber: 281,
					},
				},
				RequestID:       "00000-25c1943e-61c0-49de-93b5-cd1bf1f4020f",
				GitHubRequestID: "603B:22671E:49533C:638A05:68E48CE4",
				SkipReport:      false,
				IsVisionFlow:    false,
			},
		},
		{
			name: "TypeError with string code - ERR_INVALID_URL",
			input: `{
				"code": "ERR_INVALID_URL",
				"isVisionFlow": false,
				"message": "Invalid URL",
				"name": "TypeError",
				"skipReport": false,
				"stack": "TypeError: Invalid URL\n at new URL (node:internal/url:825:25)",
				"text": "Invalid URL"
			}`,
			expected: AgentError{
				Code: ErrorCode{
					StringValue: "ERR_INVALID_URL",
					IsString:    true,
				},
				Name:    "TypeError",
				Text:    "Invalid URL",
				Message: "Invalid URL",
				Stack:   "TypeError: Invalid URL\n at new URL (node:internal/url:825:25)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "new URL",
						FileName:   "node:internal/url",
						LineNumber: 825,
					},
				},
				SkipReport:   false,
				IsVisionFlow: false,
			},
		},
		{
			name: "GitError with numeric string code and cmd - exit code 1",
			input: `{
				"cmd": "git commit -m REDACTED",
				"code": "1",
				"isVisionFlow": false,
				"message": "hook git error: Command failed with exit code 1: git commit -m REDACTED",
				"name": "GitError",
				"skipReport": true,
				"stack": "GitError: hook git error: Command failed with exit code 1: git commit -m REDACTED\n at ay.execGit (/home/runner/work/_temp/copilot-developer-action-main/src/runner/git/default.ts:524:19)",
				"text": "hook git error: Command failed with exit code 1: git commit -m REDACTED"
			}`,
			expected: AgentError{
				Code: ErrorCode{
					StringValue: "1",
					IsString:    true,
				},
				Name:    "GitError",
				Text:    "hook git error: Command failed with exit code 1: git commit -m REDACTED",
				Message: "hook git error: Command failed with exit code 1: git commit -m REDACTED",
				Stack:   "GitError: hook git error: Command failed with exit code 1: git commit -m REDACTED\n at ay.execGit (/home/runner/work/_temp/copilot-developer-action-main/src/runner/git/default.ts:524:19)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "ay.execGit",
						FileName:   "/home/runner/work/_temp/copilot-developer-action-main/src/runner/git/default.ts",
						LineNumber: 524,
					},
				},
				Cmd:          "git commit -m REDACTED",
				SkipReport:   true,
				IsVisionFlow: false,
			},
		},
		{
			name: "CAPIError with string code - another rate_limited",
			input: `{
				"code": "rate_limited",
				"ghRequestId": "C80A:22671E:3E3402:549CAD:68E4860C",
				"isVisionFlow": false,
				"message": "429 Sorry, you have exceeded your Copilot token usage.",
				"name": "CAPIError",
				"request_id": "00000-6c26f22c-02fc-469a-8c49-707f715e1cb7",
				"skipReport": false,
				"stack": "CAPIError: 429 Sorry, you have exceeded your Copilot token usage.\n    at Function.fromAPIError (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts:281:16)",
				"text": "429 Sorry, you have exceeded your Copilot token usage."
			}`,
			expected: AgentError{
				Code: ErrorCode{
					StringValue: "rate_limited",
					IsString:    true,
				},
				Name:    "CAPIError",
				Text:    "429 Sorry, you have exceeded your Copilot token usage.",
				Message: "429 Sorry, you have exceeded your Copilot token usage.",
				Stack:   "CAPIError: 429 Sorry, you have exceeded your Copilot token usage.\n    at Function.fromAPIError (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts:281:16)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "Function.fromAPIError",
						FileName:   "/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/copilot-client.ts",
						LineNumber: 281,
					},
				},
				RequestID:       "00000-6c26f22c-02fc-469a-8c49-707f715e1cb7",
				GitHubRequestID: "C80A:22671E:3E3402:549CAD:68E4860C",
				SkipReport:      false,
				IsVisionFlow:    false,
			},
		},
		{
			name: "GitError with numeric string code - exit code 128",
			input: `{
				"cmd": "git clone REDACTED",
				"code": "128",
				"isVisionFlow": false,
				"message": "unknown git error: Command failed with exit code 128: git clone REDACTED",
				"name": "GitError",
				"skipReport": false,
				"stack": "GitError: unknown git error: Command failed with exit code 128: git clone REDACTED\n    at qz._0x41007a (/home/runner/work/_temp/copilot-developer-action-main/src/runner/git/default.ts:524:19)",
				"text": "unknown git error: Command failed with exit code 128: git clone REDACTED"
			}`,
			expected: AgentError{
				Code: ErrorCode{
					StringValue: "128",
					IsString:    true,
				},
				Name:    "GitError",
				Text:    "unknown git error: Command failed with exit code 128: git clone REDACTED",
				Message: "unknown git error: Command failed with exit code 128: git clone REDACTED",
				Stack:   "GitError: unknown git error: Command failed with exit code 128: git clone REDACTED\n    at qz._0x41007a (/home/runner/work/_temp/copilot-developer-action-main/src/runner/git/default.ts:524:19)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "qz._0x41007a",
						FileName:   "/home/runner/work/_temp/copilot-developer-action-main/src/runner/git/default.ts",
						LineNumber: 524,
					},
				},
				Cmd:          "git clone REDACTED",
				SkipReport:   false,
				IsVisionFlow: false,
			},
		},
		{
			name: "Error with string code - invalid_request_body",
			input: `{
				"code": "invalid_request_body",
				"ghRequestId": "0818:10C171:17917FE:1D2E1BA:68E48332",
				"isVisionFlow": false,
				"message": "Failed to get response from the AI model; retried 5 times (total retry wait time: 89.13140683477647 seconds)",
				"name": "Error",
				"request_id": "00000-0fbe4d0e-cc88-4358-9df0-08308b9f4d89",
				"skipReport": false,
				"stack": "Error: Failed to get response from the AI model; retried 5 times (total retry wait time: 89.13140683477647 seconds)\n    at vYI._0x354a19 (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/chat-completion-client.ts:547:40)",
				"text": "Failed to get response from the AI model; retried 5 times (total retry wait time: 89.13140683477647 seconds)"
			}`,
			expected: AgentError{
				Code: ErrorCode{
					StringValue: "invalid_request_body",
					IsString:    true,
				},
				Name:    "Error",
				Text:    "Failed to get response from the AI model; retried 5 times (total retry wait time: 89.13140683477647 seconds)",
				Message: "Failed to get response from the AI model; retried 5 times (total retry wait time: 89.13140683477647 seconds)",
				Stack:   "Error: Failed to get response from the AI model; retried 5 times (total retry wait time: 89.13140683477647 seconds)\n    at vYI._0x354a19 (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/chat-completion-client.ts:547:40)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "vYI._0x354a19",
						FileName:   "/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/chat-completion-client.ts",
						LineNumber: 547,
					},
				},
				RequestID:       "00000-0fbe4d0e-cc88-4358-9df0-08308b9f4d89",
				GitHubRequestID: "0818:10C171:17917FE:1D2E1BA:68E48332",
				SkipReport:      false,
				IsVisionFlow:    false,
			},
		},
		{
			name: "GitError with numeric string code and cmd - access denied exit code 128",
			input: `{
				"cmd": "git push -v origin REDACTED --no-verify",
				"code": "128",
				"isVisionFlow": false,
				"message": "access denied git error: Command failed with exit code 128: git push -v origin REDACTED --no-verify",
				"name": "GitError",
				"skipReport": false,
				"stack": "GitError: access denied git error: Command failed with exit code 128: git push -v origin REDACTED --no-verify\n    at qz.execGit (/home/runner/work/_temp/copilot-developer-action-main/src/runner/git/default.ts:524:19)",
				"text": "access denied git error: Command failed with exit code 128: git push -v origin REDACTED --no-verify"
			}`,
			expected: AgentError{
				Code: ErrorCode{
					StringValue: "128",
					IsString:    true,
				},
				Name:    "GitError",
				Text:    "access denied git error: Command failed with exit code 128: git push -v origin REDACTED --no-verify",
				Message: "access denied git error: Command failed with exit code 128: git push -v origin REDACTED --no-verify",
				Stack:   "GitError: access denied git error: Command failed with exit code 128: git push -v origin REDACTED --no-verify\n    at qz.execGit (/home/runner/work/_temp/copilot-developer-action-main/src/runner/git/default.ts:524:19)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "qz.execGit",
						FileName:   "/home/runner/work/_temp/copilot-developer-action-main/src/runner/git/default.ts",
						LineNumber: 524,
					},
				},
				Cmd:          "git push -v origin REDACTED --no-verify",
				SkipReport:   false,
				IsVisionFlow: false,
			},
		},
		{
			name: "Error with string code - model_max_prompt_tokens_exceeded",
			input: `{
				"code": "model_max_prompt_tokens_exceeded",
				"ghRequestId": "AC02:2D93C2:1724C4B:1CB87E4:68E4820B",
				"isVisionFlow": false,
				"message": "Failed to get response from the AI model; retried 5 times (total retry wait time: 6.171303629518614 seconds)",
				"name": "Error",
				"request_id": "00000-551f01a9-066b-4c63-b84c-5b224c79625d",
				"skipReport": false,
				"stack": "Error: Failed to get response from the AI model; retried 5 times (total retry wait time: 6.171303629518614 seconds)\n    at vYI._0x354a19 (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/chat-completion-client.ts:547:40)",
				"text": "Failed to get response from the AI model; retried 5 times (total retry wait time: 6.171303629518614 seconds)"
			}`,
			expected: AgentError{
				Code: ErrorCode{
					StringValue: "model_max_prompt_tokens_exceeded",
					IsString:    true,
				},
				Name:    "Error",
				Text:    "Failed to get response from the AI model; retried 5 times (total retry wait time: 6.171303629518614 seconds)",
				Message: "Failed to get response from the AI model; retried 5 times (total retry wait time: 6.171303629518614 seconds)",
				Stack:   "Error: Failed to get response from the AI model; retried 5 times (total retry wait time: 6.171303629518614 seconds)\n    at vYI._0x354a19 (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/chat-completion-client.ts:547:40)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "vYI._0x354a19",
						FileName:   "/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/chat-completion-client.ts",
						LineNumber: 547,
					},
				},
				RequestID:       "00000-551f01a9-066b-4c63-b84c-5b224c79625d",
				GitHubRequestID: "AC02:2D93C2:1724C4B:1CB87E4:68E4820B",
				SkipReport:      false,
				IsVisionFlow:    false,
			},
		},
		{
			name: "Error - failed to get response from AI model (no code)",
			input: `{
				"ghRequestId": "200D:2727E:15746AA:1A420F6:68E46C1F",
				"isVisionFlow": false,
				"message": "Failed to get response from the AI model; retried 5 times (total retry wait time: 92.47158283154613 seconds)",
				"name": "Error",
				"request_id": "00000-077118d3-e114-46d8-8c52-8ddf19ed130c",
				"skipReport": false,
				"stack": "Error: Failed to get response from the AI model; retried 5 times (total retry wait time: 92.47158283154613 seconds)\n    at vYI._0x354a19 (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/chat-completion-client.ts:547:40)",
				"text": "Failed to get response from the AI model; retried 5 times (total retry wait time: 92.47158283154613 seconds)"
			}`,
			expected: AgentError{
				Code:    ErrorCode{},
				Name:    "Error",
				Text:    "Failed to get response from the AI model; retried 5 times (total retry wait time: 92.47158283154613 seconds)",
				Message: "Failed to get response from the AI model; retried 5 times (total retry wait time: 92.47158283154613 seconds)",
				Stack:   "Error: Failed to get response from the AI model; retried 5 times (total retry wait time: 92.47158283154613 seconds)\n    at vYI._0x354a19 (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/chat-completion-client.ts:547:40)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "vYI._0x354a19",
						FileName:   "/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/chat-completion-client.ts",
						LineNumber: 547,
					},
				},
				RequestID:       "00000-077118d3-e114-46d8-8c52-8ddf19ed130c",
				GitHubRequestID: "200D:2727E:15746AA:1A420F6:68E46C1F",
				SkipReport:      false,
				IsVisionFlow:    false,
			},
		},
		{
			name: "Error - another failed AI model response (no code)",
			input: `{
				"ghRequestId": "AAC3:1874D8:2EB30:419DC:68E46028",
				"isVisionFlow": false,
				"message": "Failed to get response from the AI model; retried 5 times (total retry wait time: 92.61022364551911 seconds)",
				"name": "Error",
				"request_id": "00000-f3eaad46-1588-48d0-9b85-24d579b5fa8e",
				"skipReport": false,
				"stack": "Error: Failed to get response from the AI model; retried 5 times (total retry wait time: 92.61022364551911 seconds)\n    at vYI._0x354a19 (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/chat-completion-client.ts:547:40)",
				"text": "Failed to get response from the AI model; retried 5 times (total retry wait time: 92.61022364551911 seconds)"
			}`,
			expected: AgentError{
				Code:    ErrorCode{},
				Name:    "Error",
				Text:    "Failed to get response from the AI model; retried 5 times (total retry wait time: 92.61022364551911 seconds)",
				Message: "Failed to get response from the AI model; retried 5 times (total retry wait time: 92.61022364551911 seconds)",
				Stack:   "Error: Failed to get response from the AI model; retried 5 times (total retry wait time: 92.61022364551911 seconds)\n    at vYI._0x354a19 (/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/chat-completion-client.ts:547:40)",
				ParsedStack: []*goerrors.Frame{
					{
						Function:   "vYI._0x354a19",
						FileName:   "/home/runner/work/_temp/copilot-developer-action-main/src/model/capi/chat-completion-client.ts",
						LineNumber: 547,
					},
				},
				RequestID:       "00000-f3eaad46-1588-48d0-9b85-24d579b5fa8e",
				GitHubRequestID: "AAC3:1874D8:2EB30:419DC:68E46028",
				SkipReport:      false,
				IsVisionFlow:    false,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var result *AgentError
			err := json.Unmarshal([]byte(tt.input), &result)
			require.NoError(t, err, "Failed to unmarshal JSON")

			assert.Equal(t, tt.expected.Code.StringValue, result.Code.StringValue, "Code.StringValue mismatch")
			assert.Equal(t, tt.expected.Code.IntValue, result.Code.IntValue, "Code.IntValue mismatch")
			assert.Equal(t, tt.expected.Code.IsString, result.Code.IsString, "Code.IsString mismatch")
			assert.Equal(t, tt.expected.Name, result.Name, "Name mismatch")
			assert.Equal(t, tt.expected.Text, result.Text, "Text mismatch")
			assert.Equal(t, tt.expected.Message, result.Message, "Message mismatch")
			assert.Equal(t, tt.expected.Stack, result.Stack, "Stack mismatch")
			assert.Equal(t, tt.expected.ParsedStack, result.ParsedStack, "Parsed Stack mismatch")
			assert.Equal(t, tt.expected.RequestID, result.RequestID, "RequestID mismatch")
			assert.Equal(t, tt.expected.GitHubRequestID, result.GitHubRequestID, "GitHubRequestID mismatch")
			assert.Equal(t, tt.expected.Cmd, result.Cmd, "Cmd mismatch")
			assert.Equal(t, tt.expected.Signal, result.Signal, "Signal mismatch")
			assert.Equal(t, tt.expected.SkipReport, result.SkipReport, "SkipReport mismatch")
			assert.Equal(t, tt.expected.IsVisionFlow, result.IsVisionFlow, "IsVisionFlow mismatch")
		})
	}
}

func TestAgentError_UnmarshalArray(t *testing.T) {
	// Test that we can unmarshal the full array of errors
	input := `[
		{
			"ghRequestId": "1C01:3861F2:2B918D:46F0A8:68E1A098",
			"isVisionFlow": false,
			"message": "408 408 Request Timeout",
			"name": "CAPIError",
			"request_id": "00000-18e6e0c9-797e-4fa2-97d0-74efa13eb727",
			"skipReport": false,
			"stack": "CAPIError: 408 408 Request Timeout",
			"text": "408 408 Request Timeout"
		},
		{
			"code": "rate_limited",
			"ghRequestId": "603B:22671E:49533C:638A05:68E48CE4",
			"isVisionFlow": false,
			"message": "429 Sorry, you have exceeded your Copilot token usage.",
			"name": "CAPIError",
			"request_id": "00000-25c1943e-61c0-49de-93b5-cd1bf1f4020f",
			"skipReport": false,
			"stack": "CAPIError: 429 Sorry, you have exceeded your Copilot token usage.",
			"text": "429 Sorry, you have exceeded your Copilot token usage."
		},
		{
			"cmd": "git commit -m REDACTED",
			"code": "1",
			"isVisionFlow": false,
			"message": "hook git error: Command failed with exit code 1: git commit -m REDACTED",
			"name": "GitError",
			"skipReport": true,
			"stack": "GitError: hook git error",
			"text": "hook git error: Command failed with exit code 1: git commit -m REDACTED"
		}
	]`

	var errs []AgentError
	err := json.Unmarshal([]byte(input), &errs)
	require.NoError(t, err, "Failed to unmarshal array of errors")
	require.Len(t, errs, 3, "Expected 3 errors")

	// Verify first error (no code field)
	assert.Equal(t, "", errs[0].Code.StringValue)
	assert.False(t, errs[0].Code.IsString)
	assert.Equal(t, "CAPIError", errs[0].Name)
	assert.Equal(t, "408 408 Request Timeout", errs[0].Message)

	// Verify second error (string code)
	assert.Equal(t, "rate_limited", errs[1].Code.StringValue)
	assert.True(t, errs[1].Code.IsString)
	assert.Equal(t, "CAPIError", errs[1].Name)
	assert.Equal(t, "429 Sorry, you have exceeded your Copilot token usage.", errs[1].Message)

	// Verify third error (numeric string code with cmd)
	assert.Equal(t, "1", errs[2].Code.StringValue)
	assert.True(t, errs[2].Code.IsString)
	assert.Equal(t, "GitError", errs[2].Name)
	assert.Equal(t, "git commit -m REDACTED", errs[2].Cmd)
	assert.True(t, errs[2].SkipReport)
}

func TestErrorCode_UnmarshalJSON_NumericCode(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected ErrorCode
	}{
		{
			name:  "integer code",
			input: `{"code": 404}`,
			expected: ErrorCode{
				StringValue: "404",
				IntValue:    404,
				IsString:    false,
			},
		},
		{
			name:  "float code",
			input: `{"code": 500.0}`,
			expected: ErrorCode{
				StringValue: "500",
				IntValue:    500,
				IsString:    false,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var result struct {
				Code ErrorCode `json:"code"`
			}
			err := json.Unmarshal([]byte(tt.input), &result)
			require.NoError(t, err)
			assert.Equal(t, tt.expected.StringValue, result.Code.StringValue)
			assert.Equal(t, tt.expected.IntValue, result.Code.IntValue)
			assert.Equal(t, tt.expected.IsString, result.Code.IsString)
		})
	}
}

func TestAgentError_MissingProperties(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected AgentError
	}{
		{
			name:  "only name property",
			input: `{"name": "Error"}`,
			expected: AgentError{
				Name: "Error",
			},
		},
		{
			name:  "only message property",
			input: `{"message": "Something went wrong"}`,
			expected: AgentError{
				Message: "Something went wrong",
			},
		},
		{
			name:  "empty object",
			input: `{}`,
			expected: AgentError{
				Code:         ErrorCode{},
				SkipReport:   false,
				IsVisionFlow: false,
			},
		},
		{
			name: "minimal error with only required context",
			input: `{
				"name": "Error",
				"message": "Minimal error"
			}`,
			expected: AgentError{
				Name:    "Error",
				Message: "Minimal error",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var result AgentError
			err := json.Unmarshal([]byte(tt.input), &result)
			require.NoError(t, err, "Deserialization should succeed even with missing properties")

			assert.Equal(t, tt.expected.Code.StringValue, result.Code.StringValue)
			assert.Equal(t, tt.expected.Code.IsString, result.Code.IsString)
			assert.Equal(t, tt.expected.Name, result.Name)
			assert.Equal(t, tt.expected.Text, result.Text)
			assert.Equal(t, tt.expected.Message, result.Message)
			assert.Equal(t, tt.expected.Stack, result.Stack)
			assert.Equal(t, tt.expected.RequestID, result.RequestID)
			assert.Equal(t, tt.expected.GitHubRequestID, result.GitHubRequestID)
			assert.Equal(t, tt.expected.Cmd, result.Cmd)
			assert.Equal(t, tt.expected.Signal, result.Signal)
			assert.Equal(t, tt.expected.SkipReport, result.SkipReport)
			assert.Equal(t, tt.expected.IsVisionFlow, result.IsVisionFlow)
		})
	}
}

func TestAgentError_UnexpectedProperties(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected AgentError
	}{
		{
			name: "with stdout and stderr (should be ignored)",
			input: `{
				"name": "GitError",
				"message": "Command failed",
				"stdout": "some long log output\n",
				"stderr": "some long error output\n"
			}`,
			expected: AgentError{
				Name:    "GitError",
				Message: "Command failed",
			},
		},
		{
			name: "with blockedRequests array (should be ignored)",
			input: `{
				"name": "CAPIError",
				"message": "Request blocked",
				"blockedRequests": [
					{
						"because": "DomainNotInAllowlist",
						"blockedAt": "2025-10-06T14:32:15.123456Z",
						"domains": "malicious-site.com",
						"ip": "203.0.113.42"
					}
				]
			}`,
			expected: AgentError{
				Name:    "CAPIError",
				Message: "Request blocked",
			},
		},
		{
			name: "with completely unexpected properties",
			input: `{
				"name": "Error",
				"message": "Test error",
				"unknownField1": "value1",
				"unknownField2": 12345,
				"unknownObject": {
					"nested": "value"
				},
				"unknownArray": [1, 2, 3]
			}`,
			expected: AgentError{
				Name:    "Error",
				Message: "Test error",
			},
		},
		{
			name: "with mix of expected and unexpected properties",
			input: `{
				"code": "rate_limited",
				"name": "CAPIError",
				"message": "Rate limited",
				"request_id": "00000-12345",
				"ghRequestId": "ABC123",
				"skipReport": true,
				"isVisionFlow": true,
				"stdout": "ignored output",
				"stderr": "ignored error",
				"randomField": "ignored value"
			}`,
			expected: AgentError{
				Code: ErrorCode{
					StringValue: "rate_limited",
					IsString:    true,
				},
				Name:            "CAPIError",
				Message:         "Rate limited",
				RequestID:       "00000-12345",
				GitHubRequestID: "ABC123",
				SkipReport:      true,
				IsVisionFlow:    true,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var result AgentError
			err := json.Unmarshal([]byte(tt.input), &result)
			require.NoError(t, err, "Deserialization should succeed with unexpected properties")

			assert.Equal(t, tt.expected.Code.StringValue, result.Code.StringValue)
			assert.Equal(t, tt.expected.Code.IsString, result.Code.IsString)
			assert.Equal(t, tt.expected.Name, result.Name)
			assert.Equal(t, tt.expected.Text, result.Text)
			assert.Equal(t, tt.expected.Message, result.Message)
			assert.Equal(t, tt.expected.Stack, result.Stack)
			assert.Equal(t, tt.expected.RequestID, result.RequestID)
			assert.Equal(t, tt.expected.GitHubRequestID, result.GitHubRequestID)
			assert.Equal(t, tt.expected.Cmd, result.Cmd)
			assert.Equal(t, tt.expected.Signal, result.Signal)
			assert.Equal(t, tt.expected.SkipReport, result.SkipReport)
			assert.Equal(t, tt.expected.IsVisionFlow, result.IsVisionFlow)
		})
	}
}

func TestAgentError_TypeMismatches(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		shouldError bool
		expected    AgentError
	}{
		{
			name: "code as boolean (unexpected type - should fail to unmarshal code but succeed overall)",
			input: `{
				"code": true,
				"name": "Error",
				"message": "Test"
			}`,
			shouldError: false,
			expected: AgentError{
				Code:    ErrorCode{}, // Code unmarshaling fails, but error deserialization succeeds
				Name:    "Error",
				Message: "Test",
			},
		},
		{
			name: "code as array (unexpected type - should fail to unmarshal code but succeed overall)",
			input: `{
				"code": [1, 2, 3],
				"name": "Error",
				"message": "Test"
			}`,
			shouldError: false,
			expected: AgentError{
				Code:    ErrorCode{}, // Code unmarshaling fails, but error deserialization succeeds
				Name:    "Error",
				Message: "Test",
			},
		},
		{
			name: "code as object (unexpected type - should fail to unmarshal code but succeed overall)",
			input: `{
				"code": {"value": "test"},
				"name": "Error",
				"message": "Test"
			}`,
			shouldError: false,
			expected: AgentError{
				Code:    ErrorCode{}, // Code unmarshaling fails, but error deserialization succeeds
				Name:    "Error",
				Message: "Test",
			},
		},
		{
			name: "skipReport as string instead of bool",
			input: `{
				"name": "Error",
				"message": "Test",
				"skipReport": "true"
			}`,
			shouldError: true, // This will fail because bool type is strict
		},
		{
			name: "isVisionFlow as number instead of bool",
			input: `{
				"name": "Error",
				"message": "Test",
				"isVisionFlow": 1
			}`,
			shouldError: true, // This will fail because bool type is strict
		},
		{
			name: "name as number instead of string",
			input: `{
				"name": 404,
				"message": "Test"
			}`,
			shouldError: true, // This will fail because string type is strict
		},
		{
			name: "message as array instead of string",
			input: `{
				"name": "Error",
				"message": ["error", "message"]
			}`,
			shouldError: true, // This will fail because string type is strict
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var result AgentError
			err := json.Unmarshal([]byte(tt.input), &result)

			if tt.shouldError {
				assert.Error(t, err, "Expected deserialization to fail due to type mismatch")
			} else {
				require.NoError(t, err, "Deserialization should succeed even with type mismatch on code field")
				assert.Equal(t, tt.expected.Code.StringValue, result.Code.StringValue)
				assert.Equal(t, tt.expected.Code.IsString, result.Code.IsString)
				assert.Equal(t, tt.expected.Name, result.Name)
				assert.Equal(t, tt.expected.Message, result.Message)
			}
		})
	}
}

func TestAgentError_NullValues(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected AgentError
	}{
		{
			name: "null code",
			input: `{
				"code": null,
				"name": "Error",
				"message": "Test"
			}`,
			expected: AgentError{
				Code:    ErrorCode{},
				Name:    "Error",
				Message: "Test",
			},
		},
		{
			name: "null optional string fields",
			input: `{
				"name": null,
				"text": null,
				"message": "Test",
				"stack": null
			}`,
			expected: AgentError{
				Message: "Test",
			},
		},
		{
			name: "all null values",
			input: `{
				"code": null,
				"name": null,
				"text": null,
				"message": null,
				"stack": null,
				"request_id": null,
				"ghRequestId": null,
				"cmd": null,
				"signal": null
			}`,
			expected: AgentError{
				Code:         ErrorCode{},
				SkipReport:   false,
				IsVisionFlow: false,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var result AgentError
			err := json.Unmarshal([]byte(tt.input), &result)
			require.NoError(t, err, "Deserialization should succeed with null values")

			assert.Equal(t, tt.expected.Code.StringValue, result.Code.StringValue)
			assert.Equal(t, tt.expected.Code.IsString, result.Code.IsString)
			assert.Equal(t, tt.expected.Name, result.Name)
			assert.Equal(t, tt.expected.Text, result.Text)
			assert.Equal(t, tt.expected.Message, result.Message)
			assert.Equal(t, tt.expected.Stack, result.Stack)
			assert.Equal(t, tt.expected.RequestID, result.RequestID)
			assert.Equal(t, tt.expected.GitHubRequestID, result.GitHubRequestID)
			assert.Equal(t, tt.expected.Cmd, result.Cmd)
			assert.Equal(t, tt.expected.Signal, result.Signal)
			assert.Equal(t, tt.expected.SkipReport, result.SkipReport)
			assert.Equal(t, tt.expected.IsVisionFlow, result.IsVisionFlow)
		})
	}
}

func TestAgentError_Description_NoNormalization(t *testing.T) {
	tests := []struct {
		name     string
		err      AgentError
		expected string
	}{
		{
			name: "preserves retry count and seconds",
			err: AgentError{
				Message: "Failed to get response from the AI model; retried 5 times (total retry wait time: 6.171303629518614 seconds)",
			},
			expected: "Failed to get response from the AI model; retried 5 times (total retry wait time: 6.171303629518614 seconds)",
		},
		{
			name: "preserves retry count and different seconds value from Text",
			err: AgentError{
				Text: "Failed to get response from the AI model; retried 5 times (total retry wait time: 92.47158283154613 seconds)",
			},
			expected: "Failed to get response from the AI model; retried 5 times (total retry wait time: 92.47158283154613 seconds)",
		},
		{
			name: "preserves single retry and singular second",
			err: AgentError{
				Message: "Failed after retried 1 times (wait time: 1 second)",
			},
			expected: "Failed after retried 1 times (wait time: 1 second)",
		},
		{
			name: "preserves retry count and minutes",
			err: AgentError{
				Message: "Failed after retried 10 times (wait time: 30 minutes)",
			},
			expected: "Failed after retried 10 times (wait time: 30 minutes)",
		},
		{
			name: "preserves retry count and hours",
			err: AgentError{
				Message: "Failed after retried 3 times (wait time: 2.5 hours)",
			},
			expected: "Failed after retried 3 times (wait time: 2.5 hours)",
		},
		{
			name: "preserves singular hour",
			err: AgentError{
				Message: "Failed after retried 2 times (wait time: 1 hour)",
			},
			expected: "Failed after retried 2 times (wait time: 1 hour)",
		},
		{
			name: "preserves decimal minutes",
			err: AgentError{
				Message: "Failed after retried 100 times (wait time: 1.234 minutes)",
			},
			expected: "Failed after retried 100 times (wait time: 1.234 minutes)",
		},
		{
			name: "does not modify messages without retry pattern",
			err: AgentError{
				Message: "408 408 Request Timeout",
			},
			expected: "408 408 Request Timeout",
		},
		{
			name: "does not modify simple timeout messages",
			err: AgentError{
				Text: "Request timed out.",
			},
			expected: "Request timed out.",
		},
		{
			name:     "returns default when all fields empty",
			err:      AgentError{},
			expected: "An error occurred",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.err.Description()
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestAgentError_Error_StillNormalizes(t *testing.T) {
	err := AgentError{
		Name:    "CAPIError",
		Code:    ErrorCode{StringValue: "user_model_rate_limited", IsString: true},
		Message: "Failed; retried 5 times (total retry wait time: 10 minutes). Please try again in 10 minutes.",
	}
	// Description() should preserve original values for user display.
	assert.Equal(t, "Failed; retried 5 times (total retry wait time: 10 minutes). Please try again in 10 minutes.", err.Description())
	// Error() should normalize both durations and retry counts for Sentry grouping.
	assert.Contains(t, err.Error(), "<duration>")
	assert.Contains(t, err.Error(), "retried n times")
	assert.NotContains(t, err.Error(), "10 minutes")
	assert.NotContains(t, err.Error(), "retried 5 times")
}
