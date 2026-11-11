import { useRef, useState } from "react";
import {
  Form,
  Outlet,
  RouterProvider,
  createBrowserRouter,
  useMatch,
  Navigate,
  useNavigate,
  useLoaderData,
  useParams,
  Link as RouterLink,
} from "react-router-dom";
import {
  BaseStyles,
  Box,
  FormControl,
  Header,
  IconButton,
  Octicon,
  Select,
  Text,
  TextInput,
  ThemeProvider,
  Tooltip,
  themeGet,
} from "@primer/react";
import { createGlobalStyle } from "styled-components";
import { DownloadIcon, MarkGithubIcon, SearchIcon } from "@primer/octicons-react";

import ErrorPage from "./error-page";
import useHotkey, { HOTKEY_SEARCH } from "./keyboardShortcuts";
import Corpora from "./routes/corpora";
import Index, { loader as deploymentsLoader } from "./routes/deployments/index";
import BackfillIndex, { loader as backfillLoader, action as backfillAction } from "./routes/backfills/index";
import { Corpus, action as corpusAction } from "./routes/corpora/show";
import Repo, { action as repoAction, loader as repoLoader } from "./routes/repos/show";
import Fileset, { loader as filesetLoader, action as filesetAction } from "./routes/filesets/show";
import SearchResults, { loader as searchIndexLoader } from "./routes/search/index";
import User, { loader as userLoader, action as resetQuotaAction } from "./routes/users/show";
import { getClusterHosts, getCorpora, getShardAssignments, listStamps } from "./api";

const GlobalStyles = createGlobalStyle`
  html, body {
    background-color: ${themeGet("colors.canvas.default")};
    color: ${themeGet("colors.fg.default")};
  }

  html, body, #root {
    height: 100%;
  }

  ::-webkit-scrollbar {
    width: 10px;
    height: 10px;
  }

  ::-webkit-scrollbar-corner {
    background-color: ${themeGet("colors.canvas.inset")};
  }

  ::-webkit-scrollbar-track {
    background-color: ${themeGet("colors.canvas.overlay")};
  }

  ::-webkit-scrollbar-thumb {
    background-color: ${themeGet("colors.border.subtle")};
  }

  ::-webkit-scrollbar-thumb:hover {
    background-color: ${themeGet("colors.neutral.emphasis")};
  }
`;

export async function loader() {
  return await listStamps();
}

function Root() {
  const { stamps, localDev } = useLoaderData();

  const params = useParams();
  const stamp = params.stamp || "dotcom";
  const isRoot = useMatch({ path: "/", end: true });
  const isStampsRoot = useMatch({ path: "/stamps", end: true });
  const isStampRoot = useMatch({ path: `/stamps/${stamp}`, end: true });
  const isDeployments = useMatch({ path: "/deployments", end: false });
  const isBackfills = useMatch({ path: "/backfills", end: false });
  const navigate = useNavigate();
  const inputRef = useRef();

  useHotkey(HOTKEY_SEARCH, () => {
    if (inputRef.current) {
      inputRef.current.focus();
    }
  });

  const [colorMode, setColorMode] = useState(localDev ? "day" : "auto");

  if (isRoot || isStampsRoot || isStampRoot) {
    return <Navigate replace to={`/stamps/${stamp}/corpora`} />;
  }

  return (
    <ThemeProvider colorMode={colorMode} dayScheme="light" nightScheme="dark_dimmed">
      <GlobalStyles />
      <BaseStyles style={{ height: "100%" }}>
        {localDev && (
          <Box
            sx={{
              display: "flex",
              alignItems: "center",
              fontSize: 0,
              py: 0,
              px: 3,
              backgroundColor: "attention.subtle",
            }}
          >
            <Text sx={{ flex: 1 }}>local development</Text>
            <Select
              name="color_mode"
              size="small"
              value={colorMode}
              onChange={(e) => {
                setColorMode(e.target.value);
              }}
            >
              {["auto", "day", "night"].map((mode) => {
                return (
                  <Select.Option key={mode} value={mode}>
                    {mode}
                  </Select.Option>
                );
              })}
            </Select>
          </Box>
        )}
        <Header>
          <Header.Item>
            <Header.Link as={RouterLink} to={`/stamps/${stamp}/corpora`}>
              <Octicon icon={MarkGithubIcon} size={32} sx={{ mr: [0, 2] }} />
              <Box sx={{ display: ["none", "inline"] }}>Blackbird</Box>
            </Header.Link>
          </Header.Item>
          <Header.Item>|</Header.Item>
          <Header.Item>
            <Header.Link as={RouterLink} to="/deployments" sx={isDeployments ? { color: "fg.subtle" } : {}}>
              Deployments
            </Header.Link>
          </Header.Item>
          <Header.Item>|</Header.Item>
          <Header.Item>
            <Header.Link as={RouterLink} to="/backfills" sx={isBackfills ? { color: "fg.subtle" } : {}}>
              Backfills
            </Header.Link>
          </Header.Item>
          {isDeployments || isBackfills ? (
            <Header.Item full />
          ) : (
            <>
              <Header.Item full>
                <Box as="form">
                  <FormControl>
                    <FormControl.Label visuallyHidden>Stamp</FormControl.Label>
                    <Select
                      name="stamp"
                      value={stamp}
                      onChange={(e) => {
                        e.preventDefault();
                        navigate(`/stamps/${e.target.value}/corpora`);
                      }}
                    >
                      {stamps.map((s) => (
                        <Select.Option key={s} value={s}>
                          {s}
                        </Select.Option>
                      ))}
                    </Select>
                  </FormControl>
                </Box>
              </Header.Item>
              <Header.Item>
                <DownloadJSONDump stamp={stamp} />
              </Header.Item>
              <Header.Item sx={{ mr: 0, pr: 0 }}>
                <Form>
                  <TextInput
                    leadingVisual={SearchIcon}
                    ref={inputRef}
                    aria-label="User login or repo name with owner"
                    name="nwo"
                    minWidth={[20, 220]}
                    placeholder="Lookup a user, repo, or fileset"
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        const q = encodeURIComponent(e.target.value.trim());
                        navigate(`/stamps/${stamp}/repos?q=${q}`);
                      }
                    }}
                  />
                </Form>
              </Header.Item>
            </>
          )}
        </Header>
        <Outlet />
      </BaseStyles>
    </ThemeProvider>
  );
}

function DownloadJSONDump({ stamp }) {
  const downloadJSONFile = async () => {
    const [{ stamps }, corpora] = await Promise.all([listStamps(), getCorpora(stamp)]);
    const data = { stamps, corpora };

    let tasks = [];
    for (const corpus of corpora.statuses) {
      const name = corpus.corpus_name.toLowerCase();
      tasks.push(getShardAssignments(stamp, { corpus: name, offset: -1 }));
      tasks.push(getClusterHosts(stamp, { corpus: name }));
    }
    const responses = await Promise.all(tasks);
    for (const corpus of corpora.statuses) {
      const name = corpus.corpus_name.toLowerCase();
      const assignments = responses.shift();
      const hosts = responses.shift();
      data[name] = { assignments, hosts };
    }

    const json = JSON.stringify(data, null, 2);
    const blob = new Blob([json], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `${stamp}.json`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  };
  return (
    <Tooltip aria-label={`Download a JSON dump for ${stamp}`} direction="w">
      <IconButton variant="invisible" size="small" icon={DownloadIcon} onClick={downloadJSONFile}>
        Download a JSON dump for {stamp}
      </IconButton>
    </Tooltip>
  );
}

const router = createBrowserRouter([
  {
    path: "/",
    hydrateFallbackElement: <Text>Loading...</Text>,
    element: <Root />,
    loader: loader,
    errorElement: <ErrorPage />,
    children: [
      {
        path: "stamps/:stamp",
        children: [
          {
            path: "corpora",
            element: <Corpora />,
            children: [
              {
                path: ":name",
                element: <Corpus />,
                action: corpusAction,
              },
            ],
          },
          {
            path: "repos/:owner/:name",
            element: <Repo />,
            loader: repoLoader,
            action: repoAction,
          },
          {
            path: "repos/:id",
            element: <Repo />,
            loader: repoLoader,
            action: repoAction,
          },
          {
            path: "repos",
            element: <SearchResults />,
            loader: searchIndexLoader,
          },
          {
            path: "filesets/:owner/:name",
            element: <Fileset />,
            loader: filesetLoader,
            action: filesetAction,
          },
          {
            path: "filesets/:id",
            element: <Fileset />,
            loader: filesetLoader,
            action: filesetAction,
          },
          {
            path: "users/:login",
            element: <User />,
            loader: userLoader,
            action: resetQuotaAction,
          },
        ],
      },
      {
        path: "deployments",
        element: <Index />,
        loader: deploymentsLoader,
      },
      {
        path: "backfills/:cluster?",
        element: <BackfillIndex />,
        loader: backfillLoader,
        action: backfillAction,
      },
    ],
  },
]);

export default function App() {
  return <RouterProvider router={router} />;
}
