require "rails_helper"
require "manifest_adapters"

describe "pom.xml parsing" do
  def manifest(attributes = {})
    ::ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 55,
      filename: "pom.xml",
      path: "",
      content: file_fixture("pom.xml").read,
      pushed_at: Time.new(2017, 1, 1),
      fork: false,
      visibility_private: false,
    }.merge(attributes))
  end

  def dependency(args)
    ManifestAdapters::Manifest::Dependency.new(**args)
  end

  specify { expect(manifest.package_manager).to eq Types::PackageManager[:maven] }
  specify { expect(manifest.manifest_type).to eq Types::Manifest[:pom_xml] }
  specify { expect(manifest.dependent_name).to eq "com.github:iceberg" }
  specify { expect(manifest.dependent_version).to eq "1.0-SNAPSHOT" }
  specify { expect(manifest.filename).to eq "pom.xml" }
  specify { expect(manifest.path).to eq "" }
  specify { expect(manifest.git_ref).to eq "78716382bd3de2dbf141643bbe40f93185b5d4c6" }
  specify { expect(manifest.pushed_at).to eq Time.new(2017, 1, 1) }
  specify { expect(manifest.github_repository_id).to eq 55 }
  specify { expect(manifest).to_not be_fork }
  specify { expect(manifest).to_not be_malformed }

  it "parses dependencies" do
    expect(manifest.dependencies.size).to eq 29
    # includes a dependency from the main dependencies list
    expect(manifest.dependencies).to include dependency(package_name: "org.mockito:mockito-core", scope: :runtime, requirements: "= 2.17.0", raw_requirements: "2.17.0")
    # includes a dependency from a profile
    expect(manifest.dependencies).to include dependency(package_name: "org.apache.flink:flink-core", scope: :runtime, requirements: "= 1.4.0", raw_requirements: "1.4.0")
    # includes a dependency from the dependencyManagement section
    expect(manifest.dependencies).to include dependency(package_name: "group-a:artifact-a", scope: :runtime, requirements: "= 1.0", raw_requirements: "1.0")
  end

  it "parses dependencies with no version" do
    mfst = manifest(content: <<~EOF)
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>com.github</groupId>
  <artifactId>iceberg</artifactId>
  <version>1.0-SNAPSHOT</version>
  <dependencies>
    <dependency>
      <groupId>org.mockito</groupId>
      <artifactId>mockito-core</artifactId>
    </dependency>
  </dependencies>
</project>
EOF
    expect(mfst.dependencies).to contain_exactly (dependency(package_name: "org.mockito:mockito-core", scope: :runtime, requirements: "", raw_requirements: ""))
  end

  # This test does not measure a feature, it measures a limitation we have with our Maven POM parser.
  # It measures the requirement of whether we do transitive version inheritance on a POM/BOM file or not.
  it "does not parse dependencies with version declared on a parent POM/BOM" do
    mfst = manifest(content: <<~EOF)
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <parent>
    <groupId>org.github</groupId>
    <artifactId>iceberg-parent</artifactId>
    <version>1.0.0</version>
  </parent>

  <groupId>com.github</groupId>
  <artifactId>iceberg</artifactId>
  <version>1.0-SNAPSHOT</version>
  <dependencies>
    <dependency>
      <groupId>org.mockito</groupId>
      <artifactId>mockito-core</artifactId>
    </dependency>
  </dependencies>
</project>
    EOF
    expect(mfst.dependencies).to contain_exactly (dependency(package_name: "org.mockito:mockito-core", scope: :runtime, requirements: "", raw_requirements: ""))
  end

  it "parses dependencies with invalid version" do
    mfst = manifest(content: <<~EOF)
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>com.github</groupId>
  <artifactId>iceberg</artifactId>
  <version>1.0-SNAPSHOT</version>
  <dependencies>
    <dependency>
      <groupId>org.mockito</groupId>
      <artifactId>mockito-core</artifactId>
      <version>)1.0(</version>
    </dependency>
  </dependencies>
</project>
EOF
    expect(mfst.dependencies).to contain_exactly (dependency(package_name: "org.mockito:mockito-core", scope: :runtime, requirements: "", raw_requirements: ")1.0("))
  end

  it "parses dependencies with unmapped version" do
    mfst = manifest(content: <<~EOF)
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>com.github</groupId>
  <artifactId>iceberg</artifactId>
  <version>1.0-SNAPSHOT</version>
  <dependencies>
    <dependency>
      <groupId>org.mockito</groupId>
      <artifactId>mockito-core</artifactId>
      <version>${not-a-property}</version>
    </dependency>
  </dependencies>
</project>
EOF
    expect(mfst.dependencies).to contain_exactly (dependency(package_name: "org.mockito:mockito-core", scope: :runtime, requirements: "", raw_requirements: ""))
  end

   it "skips malformed dependencies" do
    mfst = manifest(content: <<~EOF)
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>com.github</groupId>
  <artifactId>iceberg</artifactId>
  <version>1.0-SNAPSHOT</version>
  <dependencies>
    <dependency>
      <groupId>org.mockito</groupId>
      <artifactId>mockito-core</artifactId>
    </dependency>
    <dependency>
      <name>Not a real thing</name>
    </dependency>
    <dependency>
      <artifactId>only-artifact</artifactId>
    </dependency>
    <dependency>
      <groupId>only-group</groupId>
    </dependency>
  </dependencies>
</project>
EOF
    expect(mfst.dependencies).to contain_exactly (dependency(package_name: "org.mockito:mockito-core", scope: :runtime, requirements: "", raw_requirements: ""))
   end

   it "sets as malformed when nokogiri finds a null byte in the xml" do
     # note this is a Nokogiri parsing error, which it can't handle null bytes
     mfst = manifest(content: "\0<xml>Max's cool xml</xml>")
     expect(mfst).to be_malformed
   end

   it "parses dependencies in dependencyManagement section" do
     mfst = manifest(content: <<~EOF)
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>com.github</groupId>
  <artifactId>iceberg</artifactId>
  <version>1.0-SNAPSHOT</version>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>org.mockito</groupId>
        <artifactId>mockito-core</artifactId>
        <version>${not-a-property}</version>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
EOF
     expect(mfst.dependencies).to contain_exactly (dependency(package_name: "org.mockito:mockito-core", scope: :runtime, requirements: "", raw_requirements: ""))
   end


   it "parses plugins and plugin dependencies as dependencies" do
     mfst = manifest(content: <<~EOF)
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>com.github</groupId>
  <artifactId>iceberg</artifactId>
  <version>1.0-SNAPSHOT</version>
  <plugins>
    <plugin>
      <groupId>org.apache.maven.plugins</groupId>
      <artifactId>maven-dependency-plugin</artifactId>
      <dependencies>
        <dependency>
          <groupId>org.mockito</groupId>
          <artifactId>mockito-core</artifactId>
        </dependency>
      </dependencies>
    </plugin>
  </plugins>
</project>
EOF
     expect(mfst.dependencies).to contain_exactly(dependency(package_name: "org.mockito:mockito-core", scope: :runtime, requirements: "", raw_requirements: ""), dependency(package_name: "org.apache.maven.plugins:maven-dependency-plugin", scope: :runtime, requirements: "", raw_requirements: ""))
   end

    it "it doesn't parse dependencies that are in other places" do
      mfst = manifest(content: <<~EOF)
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>com.github</groupId>
  <artifactId>iceberg</artifactId>
  <version>1.0-SNAPSHOT</version>
  <plugins>
    <plugin>
      <groupId>com.teradata</groupId>
      <artifactId>redlinerpm-maven-plugin-td</artifactId>
      <version>2.1.5</version>
      <extensions>true</extensions>
      <configuration>
        <performCheckingForExtraFiles>false</performCheckingForExtraFiles>
        <packages>
          <package>
            <name>presto-server-rpm</name>
            <nameOverride>presto-server-rpm-${project.version}.x86_64.rpm</nameOverride>
            <version>${project.version}</version>
            <release>1</release>

            <group>Applications/Databases</group>
            <description>Presto Server RPM Package.</description>
            <architecture>x86_64</architecture>
            <preInstallScriptFile>src/main/rpm/preinstall</preInstallScriptFile>
            <postInstallScriptFile>src/main/rpm/postinstall</postInstallScriptFile>
            <postUninstallScriptFile>src/main/rpm/postremove
            </postUninstallScriptFile>

            <dependencies>
              <dependency>
                <name>python</name>
                <version>[2.4,)</version>
              </dependency>
              <dependency>
                <name>/usr/sbin/useradd</name>
              </dependency>
              <dependency>
                <name>/usr/sbin/groupadd</name>
              </dependency>
              <dependency>
                <name>/usr/bin/uuidgen</name>
              </dependency>
            </dependencies>
          </package>
        </packages>
      </configuration>
    </plugin>
  </plugins>
</project>
EOF
     expect(mfst.dependencies).to contain_exactly(dependency(package_name: "com.teradata:redlinerpm-maven-plugin-td", scope: :runtime, requirements: "= 2.1.5", raw_requirements: "2.1.5"))
    end

  it "correctly maps names when a manifest has a parent groupId" do
    mfst = manifest(content: <<~EOF)
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>com.github.parent-group</groupId>
    <artifactId>parent</artifactId>
    <version>3.12.0-SNAPSHOT</version>
  </parent>
  <artifactId>child</artifactId>
  <version>1.0-SNAPSHOT</version>
</project>
EOF
    expect(mfst.dependent_name).to eq "com.github.parent-group:child"
  end

  it "correctly maps names when a manifest has a parent and a child groupId" do
    mfst = manifest(content: <<~EOF)
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>com.github.parent</groupId>
    <artifactId>parent-group</artifactId>
    <version>3.12.0-SNAPSHOT</version>
  </parent>
  <groupId>com.github.child-group</groupId>
  <artifactId>child</artifactId>
  <version>1.0-SNAPSHOT</version>
</project>
EOF
    expect(mfst.dependent_name).to eq "com.github.child-group:child"
  end

   it "parses manifests that use properties for groupId and artifactId" do
    mfst = manifest(content: <<~EOF)
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <groupId>${group}</groupId>
  <artifactId>${artifact}</artifactId>
  <version>1.0-SNAPSHOT</version>
  <properties>
    <group>com.github</group>
    <artifact>artifact</artifact>
    <dep_group>org.mockito</dep_group>
    <dep_artifact>mockito-core</dep_artifact>
  </properties>
  <dependencies>
    <dependency>
      <groupId>${dep_group}</groupId>
      <artifactId>${dep_artifact}</artifactId>
    </dependency>
  </dependencies>
</project>
EOF
    expect(mfst.dependent_name).to eq "com.github:artifact"
    expect(mfst.dependencies).to contain_exactly (dependency(package_name: "org.mockito:mockito-core", scope: :runtime, requirements: "", raw_requirements: ""))
   end

   it "parses single property dependencies" do
     mfst = manifest(content: <<~EOF)
 <project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
   <modelVersion>4.0.0</modelVersion>
   <groupId>com.github</groupId>
   <artifactId>iceberg</artifactId>
   <version>1.0-SNAPSHOT</version>

   <properties>
     <scala.version>2.11.12</scala.version>
   </properties>

   <dependencies>
     <dependency>
       <groupId>org.scala-lang</groupId>
       <artifactId>scala-compiler</artifactId>
       <version>${scala.version}</version>
     </dependency>
   </dependencies>
 </project>
 EOF
     expect(mfst.dependencies).to contain_exactly (dependency(package_name: "org.scala-lang:scala-compiler", scope: :runtime, requirements: "= 2.11.12", raw_requirements: "2.11.12"))
   end

   it "parses single property dependencies that merge with a plain value" do
     mfst = manifest(content: <<~EOF)
 <project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
   <modelVersion>4.0.0</modelVersion>
   <groupId>com.github</groupId>
   <artifactId>iceberg</artifactId>
   <version>1.0-SNAPSHOT</version>

   <properties>
     <scala.version>2.11</scala.version>
   </properties>

   <dependencies>
     <dependency>
       <groupId>org.scala-lang</groupId>
       <artifactId>scala-compiler</artifactId>
       <version>${scala.version}.10</version>
     </dependency>
   </dependencies>
 </project>
 EOF

 mfst2 = manifest(content: <<~EOF)
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
<modelVersion>4.0.0</modelVersion>
<groupId>com.github</groupId>
<artifactId>iceberg</artifactId>
<version>1.0-SNAPSHOT</version>

<properties>
 <scala.version>2.11</scala.version>
</properties>

<dependencies>
 <dependency>
   <groupId>org.apache.spark</groupId>
   <artifactId>spark-core_${scala.version}</artifactId>
   <version>1.10.10</version>
 </dependency>
</dependencies>
</project>
EOF
     expect(mfst.dependencies).to contain_exactly (dependency(package_name: "org.scala-lang:scala-compiler", scope: :runtime, requirements: "= 2.11.10", raw_requirements: "2.11.10"))
     expect(mfst2.dependencies).to contain_exactly (dependency(package_name: "org.apache.spark:spark-core_2.11", scope: :runtime, requirements: "= 1.10.10", raw_requirements: "1.10.10"))
   end

   it "parses multi-property dependencies" do
     mfst = manifest(content: <<~EOF)
 <project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
   <modelVersion>4.0.0</modelVersion>
   <groupId>com.github</groupId>
   <artifactId>iceberg</artifactId>
   <version>1.0-SNAPSHOT</version>

   <properties>
     <scala.version.major>2.11</scala.version.major>
     <scala.version.minor>12</scala.version.minor>
   </properties>

   <dependencies>
     <dependency>
       <groupId>org.scala-lang</groupId>
       <artifactId>scala-compiler</artifactId>
       <version>${scala.version.major}.${scala.version.minor}</version>
     </dependency>
   </dependencies>
 </project>
 EOF
     expect(mfst.dependencies).to contain_exactly (dependency(package_name: "org.scala-lang:scala-compiler", scope: :runtime, requirements: "= 2.11.12", raw_requirements: "2.11.12"))
   end

   it "parses special properties defined outside manifest" do
     mfst = manifest(content: <<~EOF)
 <project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
   <modelVersion>4.0.0</modelVersion>
   <groupId>com.github</groupId>
   <artifactId>iceberg</artifactId>
   <version>1.0-SNAPSHOT</version>

   <properties>
    <scala.version>2.11.14</scala.version>
   </properties>

   <dependencies>
     <dependency>
       <groupId>org.scala-lang</groupId>
       <artifactId>scala-compiler-${settings.compiler.version}</artifactId>
       <version>${scala.version}</version>
     </dependency>
   </dependencies>
 </project>
 EOF
     expect(mfst.dependencies).to contain_exactly (dependency(package_name: "org.scala-lang:scala-compiler-", scope: :runtime, requirements: "= 2.11.14", raw_requirements: "2.11.14"))
   end

   it "parses project.versions" do
     mfst = manifest(content: <<~EOF)
 <project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
   <modelVersion>4.0.0</modelVersion>
   <parent>
     <groupId>com.github</groupId>
     <artifactId>parent</artifactId>
     <version>3.12.0-SNAPSHOT</version>
   </parent>

   <properties>
    <scala.version>2.11.14</scala.version>
   </properties>

   <dependencies>
     <dependency>
       <groupId>org.scala-lang</groupId>
       <artifactId>scala-compiler</artifactId>
       <version>${project.version}</version>
     </dependency>
   </dependencies>
 </project>
 EOF

     mfst2 = manifest(content: <<~EOF)
 <project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
   <modelVersion>4.0.0</modelVersion>
   <groupId>com.github.parent-group</groupId>
   <artifactId>iceberg</artifactId>
   <version>3.12.0-SNAPSHOT</version>

   <properties>
    <scala.version>2.11.14</scala.version>
   </properties>

   <dependencies>
     <dependency>
       <groupId>org.scala-lang</groupId>
       <artifactId>scala-compiler</artifactId>
      <version>${project.version}</version>
     </dependency>
   </dependencies>
 </project>
 EOF

     expect(mfst.dependent_name).to eq "com.github:parent"
     expect(mfst.dependent_version).to eq "3.12.0-SNAPSHOT"
     expect(mfst.dependencies).to contain_exactly (dependency(package_name: "org.scala-lang:scala-compiler", scope: :runtime, requirements: "= 3.12.0-SNAPSHOT", raw_requirements: "3.12.0-SNAPSHOT"))
     expect(mfst2.dependencies).to contain_exactly (dependency(package_name: "org.scala-lang:scala-compiler", scope: :runtime, requirements: "= 3.12.0-SNAPSHOT", raw_requirements: "3.12.0-SNAPSHOT"))
   end

   it "parses out maven RELEASE label" do
     mfst = manifest(content: <<~EOF)
 <project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
   <modelVersion>4.0.0</modelVersion>
   <groupId>com.github</groupId>
   <artifactId>iceberg</artifactId>
   <version>1.0-SNAPSHOT</version>

   <dependencies>
     <dependency>
       <groupId>org.sarah-maven</groupId>
       <artifactId>sarah-compiler</artifactId>
       <version>2.0.0.RELEASE</version>
     </dependency>
     <dependency>
       <groupId>org.sarah-maven</groupId>
       <artifactId>sarah-debug</artifactId>
       <version>2.1.0-RELEASE</version>
     </dependency>
     <dependency>
       <groupId>org.sarah-maven</groupId>
       <artifactId>sarah-server</artifactId>
       <version>1.1.0RELEASE</version>
     </dependency>
   </dependencies>
 </project>
 EOF
     expect(mfst.dependencies).to include dependency(package_name: "org.sarah-maven:sarah-compiler", scope: :runtime, requirements: "= 2.0.0", raw_requirements: "2.0.0")
     expect(mfst.dependencies).to include dependency(package_name: "org.sarah-maven:sarah-debug", scope: :runtime, requirements: "= 2.1.0", raw_requirements: "2.1.0")
     # Not a valid use of the label
     expect(mfst.dependencies).to_not include dependency(package_name: "org.sarah-maven:sarah-server", scope: :runtime, requirements: "= 1.1.0", raw_requirements: "1.1.0")
   end
end
