drop schema ret0_admin cascade;
revoke usage on ret0.table_id_seq from ret_admin;
revoke usage on schema ret0 from ret_admin;
drop role ret_admin;
revoke postgrest_anonymous from postgrest_authenticator;
drop role postgrest_anonymous;
do 
$$ 
begin
  execute format('revoke connect on database %I from postgrest_authenticator', current_database());
end;
$$;
drop role postgrest_authenticator;
