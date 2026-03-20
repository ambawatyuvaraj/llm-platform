terraform {


  #we're using free version of terraform cloud (500 managed resources)
  cloud {
    organization = "vllmproject1"

    workspaces {
      name = "llm-platform"
    }
  }
}