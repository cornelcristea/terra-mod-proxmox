locals {
  # This is a map of template file IDs for the Proxmox templates that are downloaded and used in the module. 
  # The keys are the names of the templates, and the values are the IDs of the downloaded files.
  template_file_ids = {
    for key, file in proxmox_download_file.this :
    key => file.id
  }
}
