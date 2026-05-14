let read s = Pgsql_io.clean_string s

let select_access_token () =
  Pgsql_io.Typed_sql.(
    sql
    //
    (* access_token *)
    Ret.text
    /^ read [%blob "sql/select_gitlab_access_token.sql"]
    /% Var.bigint "installation_id")

let upsert_token () =
  Pgsql_io.Typed_sql.(
    sql
    /^ read [%blob "sql/upsert_gitlab_access_token.sql"]
    /% Var.bigint "installation_id"
    /% Var.text "access_token"
    /% Var.uuid "access_token_updated_by"
    /% Var.text "group_name")
