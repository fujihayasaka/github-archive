import {
  TwirpContext,
  TwirpServer,
  RouterEvents,
  TwirpError,
  TwirpErrorCode,
  Interceptor,
  TwirpContentType,
  chainInterceptors,
} from "twirp-ts";
import {
  GetRepositoryRequest,
  GetRepositoryResponse,
  ListRepositoriesRequest,
  ListRepositoriesResponse,
} from "./secret_scanning_repositories_api";

//==================================//
//          Client Code             //
//==================================//

interface Rpc {
  request(
    service: string,
    method: string,
    contentType: "application/json" | "application/protobuf",
    data: object | Uint8Array
  ): Promise<object | Uint8Array>;
}

export interface RepositoryAPIClient {
  GetRepository(request: GetRepositoryRequest): Promise<GetRepositoryResponse>;
  ListRepositories(
    request: ListRepositoriesRequest
  ): Promise<ListRepositoriesResponse>;
}

export class RepositoryAPIClientJSON implements RepositoryAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetRepository.bind(this);
    this.ListRepositories.bind(this);
  }
  GetRepository(request: GetRepositoryRequest): Promise<GetRepositoryResponse> {
    const data = GetRepositoryRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.repositories.v1.RepositoryAPI",
      "GetRepository",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetRepositoryResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  ListRepositories(
    request: ListRepositoriesRequest
  ): Promise<ListRepositoriesResponse> {
    const data = ListRepositoriesRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.repositories.v1.RepositoryAPI",
      "ListRepositories",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      ListRepositoriesResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class RepositoryAPIClientProtobuf implements RepositoryAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetRepository.bind(this);
    this.ListRepositories.bind(this);
  }
  GetRepository(request: GetRepositoryRequest): Promise<GetRepositoryResponse> {
    const data = GetRepositoryRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.repositories.v1.RepositoryAPI",
      "GetRepository",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetRepositoryResponse.fromBinary(data as Uint8Array)
    );
  }

  ListRepositories(
    request: ListRepositoriesRequest
  ): Promise<ListRepositoriesResponse> {
    const data = ListRepositoriesRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.repositories.v1.RepositoryAPI",
      "ListRepositories",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      ListRepositoriesResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface RepositoryAPITwirp<T extends TwirpContext = TwirpContext> {
  GetRepository(
    ctx: T,
    request: GetRepositoryRequest
  ): Promise<GetRepositoryResponse>;
  ListRepositories(
    ctx: T,
    request: ListRepositoriesRequest
  ): Promise<ListRepositoriesResponse>;
}

export enum RepositoryAPIMethod {
  GetRepository = "GetRepository",
  ListRepositories = "ListRepositories",
}

export const RepositoryAPIMethodList = [
  RepositoryAPIMethod.GetRepository,
  RepositoryAPIMethod.ListRepositories,
];

export function createRepositoryAPIServer<
  T extends TwirpContext = TwirpContext
>(service: RepositoryAPITwirp<T>) {
  return new TwirpServer<RepositoryAPITwirp, T>({
    service,
    packageName: "github.secretscanning.repositories.v1",
    serviceName: "RepositoryAPI",
    methodList: RepositoryAPIMethodList,
    matchRoute: matchRepositoryAPIRoute,
  });
}

function matchRepositoryAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "GetRepository":
      return async (
        ctx: T,
        service: RepositoryAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetRepositoryRequest,
          GetRepositoryResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetRepository" };
        await events.onMatch(ctx);
        return handleRepositoryAPIGetRepositoryRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "ListRepositories":
      return async (
        ctx: T,
        service: RepositoryAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          ListRepositoriesRequest,
          ListRepositoriesResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "ListRepositories" };
        await events.onMatch(ctx);
        return handleRepositoryAPIListRepositoriesRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    default:
      events.onNotFound();
      const msg = `no handler found`;
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleRepositoryAPIGetRepositoryRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: RepositoryAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetRepositoryRequest, GetRepositoryResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleRepositoryAPIGetRepositoryJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleRepositoryAPIGetRepositoryProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleRepositoryAPIListRepositoriesRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: RepositoryAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListRepositoriesRequest,
    ListRepositoriesResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleRepositoryAPIListRepositoriesJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleRepositoryAPIListRepositoriesProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}
async function handleRepositoryAPIGetRepositoryJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: RepositoryAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetRepositoryRequest, GetRepositoryResponse>[]
) {
  let request: GetRepositoryRequest;
  let response: GetRepositoryResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetRepositoryRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetRepositoryRequest,
      GetRepositoryResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetRepository(ctx, inputReq);
    });
  } else {
    response = await service.GetRepository(ctx, request!);
  }

  return JSON.stringify(
    GetRepositoryResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleRepositoryAPIListRepositoriesJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: RepositoryAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListRepositoriesRequest,
    ListRepositoriesResponse
  >[]
) {
  let request: ListRepositoriesRequest;
  let response: ListRepositoriesResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = ListRepositoriesRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ListRepositoriesRequest,
      ListRepositoriesResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListRepositories(ctx, inputReq);
    });
  } else {
    response = await service.ListRepositories(ctx, request!);
  }

  return JSON.stringify(
    ListRepositoriesResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleRepositoryAPIGetRepositoryProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: RepositoryAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetRepositoryRequest, GetRepositoryResponse>[]
) {
  let request: GetRepositoryRequest;
  let response: GetRepositoryResponse;

  try {
    request = GetRepositoryRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetRepositoryRequest,
      GetRepositoryResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetRepository(ctx, inputReq);
    });
  } else {
    response = await service.GetRepository(ctx, request!);
  }

  return Buffer.from(GetRepositoryResponse.toBinary(response));
}

async function handleRepositoryAPIListRepositoriesProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: RepositoryAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListRepositoriesRequest,
    ListRepositoriesResponse
  >[]
) {
  let request: ListRepositoriesRequest;
  let response: ListRepositoriesResponse;

  try {
    request = ListRepositoriesRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ListRepositoriesRequest,
      ListRepositoriesResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListRepositories(ctx, inputReq);
    });
  } else {
    response = await service.ListRepositories(ctx, request!);
  }

  return Buffer.from(ListRepositoriesResponse.toBinary(response));
}
