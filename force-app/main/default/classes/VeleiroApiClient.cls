/**
 * Cliente HTTP para la API de Veleiro (https://app.veleiro.ai/api/v1 por defecto).
 * Server-to-server (Apex). Respeta el contrato:
 *  - rutas SIN slash final (trampa 1),
 *  - envelope {"data": ...} con has_more / next_cursor,
 *  - paginacion por cursor firmado (sin offset),
 *  - errores {"error":{code,...}} -> se ramifica por CODE, nunca por message,
 *  - 429 con Retry-After,
 *  - concurrencia con version / If-Match; 409 version_conflict trae detail.current_version.
 */
public with sharing class VeleiroApiClient {

    public class VeleiroApiException extends Exception {
        public String code;
        public Integer currentVersion; // presente en 409 version_conflict
    }

    // Defaults NO-secretos: el partner solo tiene que pegar su token; base URLs caen a estos.
    private static final String DEFAULT_BASE = 'callout:Veleiro_API/api/v1'; // via Named Credential Veleiro_API
    private static final String DEFAULT_APP_BASE = 'https://app.veleiro.ai'; // produccion por defecto (beta: app.beta.veleiro.dev)

    // Lo UNICO obligatorio que el partner configura es el token (un secreto). Base_Url es opcional.
    private static Veleiro_Config__c cfg() {
        Veleiro_Config__c c = resolveConfig();
        if (c == null || String.isBlank(c.Api_Token__c)) {
            throw new VeleiroApiException('Falta el token de Veleiro. Pega tu Api_Token__c en Setup > Custom Settings > Veleiro Config.');
        }
        return c;
    }

    // Resuelve la config SIN importar el nivel/"Location" (Org Default, Perfil o Usuario):
    // 1) getInstance() (jerarquia del usuario actual), 2) getOrgDefaults(), 3) cualquier registro con token.
    private static Veleiro_Config__c resolveConfig() {
        Veleiro_Config__c c = Veleiro_Config__c.getInstance();
        if (c != null && String.isNotBlank(c.Api_Token__c)) return c;
        c = Veleiro_Config__c.getOrgDefaults();
        if (c != null && String.isNotBlank(c.Api_Token__c)) return c;
        List<Veleiro_Config__c> found = [
            SELECT Api_Token__c, Base_Url__c, App_Base_Url__c
            FROM Veleiro_Config__c WHERE Api_Token__c != null LIMIT 1
        ];
        return found.isEmpty() ? c : found[0];
    }

    // TRUE si hay un token configurado (en cualquier nivel). No expone el token.
    public static Boolean hasToken() {
        Veleiro_Config__c c = resolveConfig();
        return c != null && String.isNotBlank(c.Api_Token__c);
    }

    // Base de la API: usa la configurada si es valida; si viene vacia o malformada, cae al default.
    private static String baseUrl(Veleiro_Config__c c) {
        String u = (c != null) ? c.Base_Url__c : null;
        if (String.isNotBlank(u) && (u.startsWith('callout:') || u.startsWithIgnoreCase('http'))) {
            return u;
        }
        return DEFAULT_BASE; // vacio o malformado (ej. sin el prefijo callout:) -> default correcto
    }

    // URL base humana del portal de Veleiro para los links "Open in Veleiro" (cualquier nivel de config).
    public static String appBaseUrl() {
        Veleiro_Config__c c = resolveConfig();
        String u = (c != null) ? c.App_Base_Url__c : null;
        return String.isNotBlank(u) ? u.removeEnd('/') : DEFAULT_APP_BASE;
    }

    // Base de API configurada (el string callout:..., NO secreto). Para mostrar el entorno en el panel.
    public static String apiBaseConfigured() {
        return baseUrl(resolveConfig());
    }

    private static HttpRequest baseReq(String method, String path) {
        Veleiro_Config__c c = cfg();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(baseUrl(c) + path); // el path NO lleva slash final
        req.setMethod(method);
        req.setHeader('Authorization', 'Bearer ' + c.Api_Token__c);
        req.setHeader('Accept', 'application/json');
        req.setTimeout(120000);
        return req;
    }

    // Interpreta la respuesta; si es error, lanza VeleiroApiException con code (+ current_version en 409).
    private static Map<String, Object> handle(HttpResponse res) {
        Integer status = res.getStatusCode();
        Map<String, Object> body;
        try {
            body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } catch (Exception e) {
            VeleiroApiException ex = new VeleiroApiException('Respuesta no-JSON (HTTP ' + status + '): ' + res.getBody());
            ex.code = 'internal_error';
            throw ex;
        }
        if (status >= 200 && status < 300) {
            return body;
        }
        VeleiroApiException ex = new VeleiroApiException();
        ex.code = 'internal_error';
        String msg = res.getBody();
        Object errObj = (body != null) ? body.get('error') : null;
        if (errObj instanceof Map<String, Object>) {
            Map<String, Object> err = (Map<String, Object>) errObj;
            if (err.get('code') != null) ex.code = (String) err.get('code');
            if (err.get('message') != null) msg = (String) err.get('message');
            Object det = err.get('detail');
            if (det instanceof Map<String, Object> && ((Map<String, Object>) det).get('current_version') != null) {
                ex.currentVersion = Integer.valueOf(String.valueOf(((Map<String, Object>) det).get('current_version')));
            }
        }
        if (status == 429) ex.code = 'rate_limited';
        ex.setMessage(ex.code + ': ' + msg);
        throw ex;
    }

    // ---------- Lectura ----------

    public static Map<String, Object> doGet(String path, Map<String, String> query) {
        String qs = '';
        if (query != null && !query.isEmpty()) {
            List<String> parts = new List<String>();
            for (String k : query.keySet()) {
                parts.add(EncodingUtil.urlEncode(k, 'UTF-8') + '=' + EncodingUtil.urlEncode(query.get(k), 'UTF-8'));
            }
            qs = '?' + String.join(parts, '&');
        }
        HttpRequest req = baseReq('GET', path + qs);
        return handle(new Http().send(req));
    }

    // Lista completa siguiendo el cursor hasta has_more=false.
    public static List<Object> listAll(String path, Map<String, String> filters) {
        List<Object> all = new List<Object>();
        Map<String, String> q = (filters != null) ? filters.clone() : new Map<String, String>();
        q.put('limit', '100');
        Integer guard = 0;
        while (true) {
            Map<String, Object> body = doGet(path, q);
            Object data = body.get('data');
            if (data instanceof List<Object>) all.addAll((List<Object>) data);
            Boolean hasMore = (body.get('has_more') == true);
            String next = (String) body.get('next_cursor');
            if (!hasMore || String.isBlank(next) || guard++ >= 100) break;
            q.put('cursor', next);
        }
        return all;
    }

    // ---------- Escritura ----------

    // POST -> crea. Devuelve el recurso creado (data).
    public static Map<String, Object> doPost(String path, Map<String, Object> payload) {
        HttpRequest req = baseReq('POST', path);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        Map<String, Object> body = handle(new Http().send(req));
        return (Map<String, Object>) body.get('data');
    }

    // PATCH parcial. Si ifMatchVersion != null, escritura condicional (If-Match).
    // OJO: additional_fields se REEMPLAZA entero (no se mergea) -> mandar el mapa completo.
    public static Map<String, Object> doPatch(String path, Map<String, Object> payload, Integer ifMatchVersion) {
        HttpRequest req = baseReq('PATCH', path);
        req.setHeader('Content-Type', 'application/json');
        if (ifMatchVersion != null) req.setHeader('If-Match', String.valueOf(ifMatchVersion));
        req.setBody(JSON.serialize(payload));
        Map<String, Object> body = handle(new Http().send(req));
        return (Map<String, Object>) body.get('data');
    }
}
