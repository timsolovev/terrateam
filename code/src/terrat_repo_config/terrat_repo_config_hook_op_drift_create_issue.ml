module Group_by = struct
  let t_of_yojson = function
    | `String "all" -> Ok `All
    | `String "dirspace" -> Ok `Dirspace
    | json -> Error ("Unknown value: " ^ Yojson.Safe.pretty_to_string json)

  let t_to_yojson = function
    | `All -> `String "all"
    | `Dirspace -> `String "dirspace"

  type t =
    ([ `All
     | `Dirspace
     ]
    [@of_yojson t_of_yojson] [@to_yojson t_to_yojson])
  [@@deriving yojson { strict = false; meta = true }, show, eq]
end

module Type = struct
  let t_of_yojson = function
    | `String "drift_create_issue" -> Ok `Drift_create_issue
    | json -> Error ("Unknown value: " ^ Yojson.Safe.pretty_to_string json)

  let t_to_yojson = function
    | `Drift_create_issue -> `String "drift_create_issue"

  type t = ([ `Drift_create_issue ][@of_yojson t_of_yojson] [@to_yojson t_to_yojson])
  [@@deriving yojson { strict = false; meta = true }, show, eq]
end

type t = {
  group_by : Group_by.t; [@default `All]
  type_ : Type.t option; [@key "type"] [@default None]
}
[@@deriving yojson { strict = true; meta = true }, make, show, eq]
