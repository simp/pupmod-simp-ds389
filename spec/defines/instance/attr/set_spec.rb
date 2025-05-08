# frozen_string_literal: true

require 'spec_helper'

describe 'ds389::instance::attr::set', type: :define do
  context 'when on supported operating systems' do
    on_supported_os.each do |os, os_facts|
      context "with #{os}" do
        let(:facts) do
          os_facts
        end

        let(:title) do
          'test'
        end

        let(:params) do
          {
            key: 'test_key',
            value: 'test_value',
            root_dn: 'dn=thing',
            root_pw_file: '/some/seekrit/file.skrt',
            instance_name: 'my_service'
          }
        end

        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to create_exec("Set cn=config,#{params[:key]} on #{params[:instance_name]}")
            .with_command(
              sensitive(
                # rubocop:disable Layout/LineLength
                %(echo -e "dn: cn=config\\nchangetype: modify\\nreplace: #{params[:key]}\\n#{params[:key]}: #{params[:value]}" | ldapmodify -x -D '#{params[:root_dn]}' -y '#{params[:root_pw_file]}' -H ldap://127.0.0.1:389),
                # rubocop:enable Layout/LineLength
              ),
            )
            .with_unless(
              sensitive(
                # rubocop:disable Layout/LineLength
                %(ldapsearch -x -D '#{params[:root_dn]}' -y '#{params[:root_pw_file]}' -H ldap://127.0.0.1:389 -LLL -s base -S '' -a always -o ldif-wrap=no -b 'cn=config' '#{params[:key]}' | grep -x '#{params[:key]}: #{params[:value]}'),
                # rubocop:enable Layout/LineLength
              ),
            )
            .with_path(['/bin', '/usr/bin'])
        }

        it { is_expected.not_to create_service(params[:instance_name]) }

        context 'when restarting the service' do
          let(:params) do
            {
              key: 'test_key',
              value: 'test_value',
              root_dn: 'dn=thing',
              root_pw_file: '/some/seekrit/file.skrt',
              instance_name: 'my_service',
              restart_instance: true
            }
          end

          it { is_expected.to compile.with_all_deps }

          it { is_expected.to create_ds389__instance__service(params[:instance_name]) }

          it {
            is_expected.to create_exec("Restart #{params[:instance_name]}")
              .with_command("/sbin/restart-dirsrv #{params[:instance_name]}")
              .with_refreshonly(true)
              .that_requires("Exec[Set cn=config,#{params[:key]} on #{params[:instance_name]}]")
          }
        end
      end
    end
  end
end
