module Make
    (_ : Terrat_vcs_service.S with type Service.vcs_config = Terrat_config.Github.t)
    (_ : Terrat_vcs_service.S with type Service.vcs_config = Terrat_config.Gitlab.t) : sig end
