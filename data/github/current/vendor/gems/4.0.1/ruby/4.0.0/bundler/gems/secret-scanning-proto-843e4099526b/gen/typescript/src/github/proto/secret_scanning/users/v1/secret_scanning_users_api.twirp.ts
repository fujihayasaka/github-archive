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
  FindUsersRequest,
  FindUsersResponse,
  GetSecretAuthorRequest,
  GetSecretAuthorResponse,
  GetEnterprisesForUserRequest,
  GetEnterprisesForUserResponse,
} from "./secret_scanning_users_api";

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

export interface UsersAPIClient {
  FindUsers(request: FindUsersRequest): Promise<FindUsersResponse>;
  GetSecretAuthor(
    request: GetSecretAuthorRequest
  ): Promise<GetSecretAuthorResponse>;
  GetEnterprisesForUser(
    request: GetEnterprisesForUserRequest
  ): Promise<GetEnterprisesForUserResponse>;
}

export class UsersAPIClientJSON implements UsersAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.FindUsers.bind(this);
    this.GetSecretAuthor.bind(this);
    this.GetEnterprisesForUser.bind(this);
  }
  FindUsers(request: FindUsersRequest): Promise<FindUsersResponse> {
    const data = FindUsersRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.users.v1.UsersAPI",
      "FindUsers",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      FindUsersResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  GetSecretAuthor(
    request: GetSecretAuthorRequest
  ): Promise<GetSecretAuthorResponse> {
    const data = GetSecretAuthorRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.users.v1.UsersAPI",
      "GetSecretAuthor",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetSecretAuthorResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetEnterprisesForUser(
    request: GetEnterprisesForUserRequest
  ): Promise<GetEnterprisesForUserResponse> {
    const data = GetEnterprisesForUserRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.users.v1.UsersAPI",
      "GetEnterprisesForUser",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetEnterprisesForUserResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class UsersAPIClientProtobuf implements UsersAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.FindUsers.bind(this);
    this.GetSecretAuthor.bind(this);
    this.GetEnterprisesForUser.bind(this);
  }
  FindUsers(request: FindUsersRequest): Promise<FindUsersResponse> {
    const data = FindUsersRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.users.v1.UsersAPI",
      "FindUsers",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      FindUsersResponse.fromBinary(data as Uint8Array)
    );
  }

  GetSecretAuthor(
    request: GetSecretAuthorRequest
  ): Promise<GetSecretAuthorResponse> {
    const data = GetSecretAuthorRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.users.v1.UsersAPI",
      "GetSecretAuthor",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetSecretAuthorResponse.fromBinary(data as Uint8Array)
    );
  }

  GetEnterprisesForUser(
    request: GetEnterprisesForUserRequest
  ): Promise<GetEnterprisesForUserResponse> {
    const data = GetEnterprisesForUserRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.users.v1.UsersAPI",
      "GetEnterprisesForUser",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetEnterprisesForUserResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface UsersAPITwirp<T extends TwirpContext = TwirpContext> {
  FindUsers(ctx: T, request: FindUsersRequest): Promise<FindUsersResponse>;
  GetSecretAuthor(
    ctx: T,
    request: GetSecretAuthorRequest
  ): Promise<GetSecretAuthorResponse>;
  GetEnterprisesForUser(
    ctx: T,
    request: GetEnterprisesForUserRequest
  ): Promise<GetEnterprisesForUserResponse>;
}

export enum UsersAPIMethod {
  FindUsers = "FindUsers",
  GetSecretAuthor = "GetSecretAuthor",
  GetEnterprisesForUser = "GetEnterprisesForUser",
}

export const UsersAPIMethodList = [
  UsersAPIMethod.FindUsers,
  UsersAPIMethod.GetSecretAuthor,
  UsersAPIMethod.GetEnterprisesForUser,
];

export function createUsersAPIServer<T extends TwirpContext = TwirpContext>(
  service: UsersAPITwirp<T>
) {
  return new TwirpServer<UsersAPITwirp, T>({
    service,
    packageName: "github.secretscanning.users.v1",
    serviceName: "UsersAPI",
    methodList: UsersAPIMethodList,
    matchRoute: matchUsersAPIRoute,
  });
}

function matchUsersAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "FindUsers":
      return async (
        ctx: T,
        service: UsersAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<T, FindUsersRequest, FindUsersResponse>[]
      ) => {
        ctx = { ...ctx, methodName: "FindUsers" };
        await events.onMatch(ctx);
        return handleUsersAPIFindUsersRequest(ctx, service, data, interceptors);
      };
    case "GetSecretAuthor":
      return async (
        ctx: T,
        service: UsersAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetSecretAuthorRequest,
          GetSecretAuthorResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetSecretAuthor" };
        await events.onMatch(ctx);
        return handleUsersAPIGetSecretAuthorRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetEnterprisesForUser":
      return async (
        ctx: T,
        service: UsersAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetEnterprisesForUserRequest,
          GetEnterprisesForUserResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetEnterprisesForUser" };
        await events.onMatch(ctx);
        return handleUsersAPIGetEnterprisesForUserRequest(
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

function handleUsersAPIFindUsersRequest<T extends TwirpContext = TwirpContext>(
  ctx: T,
  service: UsersAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, FindUsersRequest, FindUsersResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleUsersAPIFindUsersJSON<T>(ctx, service, data, interceptors);
    case TwirpContentType.Protobuf:
      return handleUsersAPIFindUsersProtobuf<T>(
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

function handleUsersAPIGetSecretAuthorRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: UsersAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetSecretAuthorRequest,
    GetSecretAuthorResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleUsersAPIGetSecretAuthorJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleUsersAPIGetSecretAuthorProtobuf<T>(
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

function handleUsersAPIGetEnterprisesForUserRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: UsersAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetEnterprisesForUserRequest,
    GetEnterprisesForUserResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleUsersAPIGetEnterprisesForUserJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleUsersAPIGetEnterprisesForUserProtobuf<T>(
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
async function handleUsersAPIFindUsersJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: UsersAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, FindUsersRequest, FindUsersResponse>[]
) {
  let request: FindUsersRequest;
  let response: FindUsersResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = FindUsersRequest.fromJson(body, { ignoreUnknownFields: true });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      FindUsersRequest,
      FindUsersResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.FindUsers(ctx, inputReq);
    });
  } else {
    response = await service.FindUsers(ctx, request!);
  }

  return JSON.stringify(
    FindUsersResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleUsersAPIGetSecretAuthorJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: UsersAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetSecretAuthorRequest,
    GetSecretAuthorResponse
  >[]
) {
  let request: GetSecretAuthorRequest;
  let response: GetSecretAuthorResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetSecretAuthorRequest.fromJson(body, {
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
      GetSecretAuthorRequest,
      GetSecretAuthorResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetSecretAuthor(ctx, inputReq);
    });
  } else {
    response = await service.GetSecretAuthor(ctx, request!);
  }

  return JSON.stringify(
    GetSecretAuthorResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleUsersAPIGetEnterprisesForUserJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: UsersAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetEnterprisesForUserRequest,
    GetEnterprisesForUserResponse
  >[]
) {
  let request: GetEnterprisesForUserRequest;
  let response: GetEnterprisesForUserResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetEnterprisesForUserRequest.fromJson(body, {
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
      GetEnterprisesForUserRequest,
      GetEnterprisesForUserResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetEnterprisesForUser(ctx, inputReq);
    });
  } else {
    response = await service.GetEnterprisesForUser(ctx, request!);
  }

  return JSON.stringify(
    GetEnterprisesForUserResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleUsersAPIFindUsersProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: UsersAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, FindUsersRequest, FindUsersResponse>[]
) {
  let request: FindUsersRequest;
  let response: FindUsersResponse;

  try {
    request = FindUsersRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      FindUsersRequest,
      FindUsersResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.FindUsers(ctx, inputReq);
    });
  } else {
    response = await service.FindUsers(ctx, request!);
  }

  return Buffer.from(FindUsersResponse.toBinary(response));
}

async function handleUsersAPIGetSecretAuthorProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: UsersAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetSecretAuthorRequest,
    GetSecretAuthorResponse
  >[]
) {
  let request: GetSecretAuthorRequest;
  let response: GetSecretAuthorResponse;

  try {
    request = GetSecretAuthorRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetSecretAuthorRequest,
      GetSecretAuthorResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetSecretAuthor(ctx, inputReq);
    });
  } else {
    response = await service.GetSecretAuthor(ctx, request!);
  }

  return Buffer.from(GetSecretAuthorResponse.toBinary(response));
}

async function handleUsersAPIGetEnterprisesForUserProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: UsersAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetEnterprisesForUserRequest,
    GetEnterprisesForUserResponse
  >[]
) {
  let request: GetEnterprisesForUserRequest;
  let response: GetEnterprisesForUserResponse;

  try {
    request = GetEnterprisesForUserRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetEnterprisesForUserRequest,
      GetEnterprisesForUserResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetEnterprisesForUser(ctx, inputReq);
    });
  } else {
    response = await service.GetEnterprisesForUser(ctx, request!);
  }

  return Buffer.from(GetEnterprisesForUserResponse.toBinary(response));
}
