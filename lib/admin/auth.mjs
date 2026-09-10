export const json = (response, status, body) => {
  response.statusCode = status;
  response.setHeader("Content-Type", "application/json");
  response.end(JSON.stringify(body));
};

export const getAdminCredentials = () => ({
  username: process.env.ADMIN_USERNAME ?? "kojiychan",
  password: process.env.ADMIN_PASSWORD ?? "Test123",
});

export const parseBasicAuth = (header = "") => {
  const [scheme, encoded] = header.split(" ");
  if (scheme !== "Basic" || !encoded) {
    return null;
  }

  const decoded = Buffer.from(encoded, "base64").toString("utf8");
  const separatorIndex = decoded.indexOf(":");
  if (separatorIndex === -1) {
    return null;
  }

  return {
    username: decoded.slice(0, separatorIndex),
    password: decoded.slice(separatorIndex + 1),
  };
};

export const isAuthorizedAdmin = (request) => {
  const credentials = getAdminCredentials();
  const auth = parseBasicAuth(request.headers?.authorization);
  return auth?.username === credentials.username && auth?.password === credentials.password;
};

export const requireAdmin = (request, response) => {
  if (isAuthorizedAdmin(request)) {
    return true;
  }

  response.setHeader("WWW-Authenticate", 'Basic realm="Eleph Admin"');
  json(response, 401, { error: "Admin login required" });
  return false;
};
