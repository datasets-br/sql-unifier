UPDATE dataset.meta 
SET  kx_fields=dataset.metaget_schema_field(info,'name'),
     kx_types=dataset.metaget_schema_field(info,'type')
;

