# frozen_string_literal: true

require 'spec_helper'

describe 'ds389::config::item', type: :define do
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
            admin_dn: 'dn=thing',
            pw_file: '/some/seekrit/file.skrt',
            service_name: 'my_service'
          }
        end

        it { is_expected.to compile.with_all_deps }

        it {
          expect(subject).to create_exec("Set cn=config,#{params[:key]} on dirsrv@#{params[:service_name]}")
            .with_command(
              # rubocop:disable Layout/LineLength
              %(echo -e "dn: cn=config\\nchangetype: modify\\nreplace: #{params[:key]}\\n#{params[:key]}: #{params[:value]}" | ldapmodify  -x -D '#{params[:admin_dn]}' -y '#{params[:pw_file]}' -H ldap://127.0.0.1:389),
              # rubocop:enable Layout/LineLength
            )
            .with_unless(
              # rubocop:disable Layout/LineLength
              %(test `ldapsearch  -x -D '#{params[:admin_dn]}' -y '#{params[:pw_file]}' -H ldap://127.0.0.1:389 -LLL -s base -b 'cn=config' '#{params[:key]}' | grep -e '^#{params[:key]}' | awk '{ print $2 }'` == '#{params[:value]}'),
              # rubocop:enable Layout/LineLength
            )
            .with_path(['/bin', '/usr/bin'])
        }

        it { is_expected.not_to create_service("dirsrv@#{params[:service_name]}") }

        context 'when restarting the service' do
          let(:params) do
            {
              key: 'test_key',
              value: 'test_value',
              admin_dn: 'dn=thing',
              pw_file: '/some/seekrit/file.skrt',
              service_name: 'dirsrv@my_service',
              restart_service: true
            }
          end

          it { is_expected.to compile.with_all_deps }

          it { is_expected.to create_service(params[:service_name]) }

          it {
            expect(subject).to create_exec("Set cn=config,#{params[:key]} on #{params[:service_name]}")
              .that_notifies("Service[#{params[:service_name]}]")
          }
        end
      end
    end
  end
end
