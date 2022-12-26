{stdenv, lib, unzip, mkLicenses}:
{packages, os ? null, buildInputs ? [], patchesInstructions ? {}, meta ? {}, ...}@args:

let
  extraParams = removeAttrs args [ "packages" "os" "buildInputs" "patchesInstructions" ];
  sortedPackages = builtins.sort (x: y: builtins.lessThan x.name y.name) packages;


  mkXmlAttrs = attrs:
    lib.concatStrings (lib.mapAttrsToList (name: value: " ${name}=\"${value}\"") attrs);
  mkXmlValues = attrs:
    lib.concatStrings (lib.mapAttrsToList (name: value:
      if builtins.typeOf value == "string" then "<${name}>${value}</${name}>" else mkXmlDoc name value
    ) attrs);
  mkXmlDoc = name: doc: "<${name}${
      let
        hasAttr = builtins.hasAttr "element-attributes" doc;
        docWithoutAttr = removeAttrs doc [ "element-attributes" ];
        hasNonAttrElement = builtins.length (builtins.attrNames docWithoutAttr) > 0;
      in
        if hasAttr && hasNonAttrElement then "${mkXmlAttrs doc.element-attributes}>${mkXmlValues docWithoutAttr}</${name}>"
        else if hasAttr && !hasNonAttrElement then "${mkXmlAttrs doc.element-attributes}/>"
        else if !hasAttr && hasNonAttrElement then ">${mkXmlValues docWithoutAttr}</${name}>"
        else "/>"
    }";
  mkXmlPackage = package: ''
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <ns2:repository
      xmlns:ns2="http://schemas.android.com/repository/android/common/02"
      xmlns:ns3="http://schemas.android.com/repository/android/common/01"
      xmlns:ns4="http://schemas.android.com/repository/android/generic/01"
      xmlns:ns5="http://schemas.android.com/repository/android/generic/02"
      xmlns:ns6="http://schemas.android.com/sdk/android/repo/addon2/01"
      xmlns:ns7="http://schemas.android.com/sdk/android/repo/addon2/02"
      xmlns:ns8="http://schemas.android.com/sdk/android/repo/addon2/03"
      xmlns:ns9="http://schemas.android.com/sdk/android/repo/repository2/01"
      xmlns:ns10="http://schemas.android.com/sdk/android/repo/repository2/02"
      xmlns:ns11="http://schemas.android.com/sdk/android/repo/repository2/03"
      xmlns:ns12="http://schemas.android.com/sdk/android/repo/sys-img2/03"
      xmlns:ns13="http://schemas.android.com/sdk/android/repo/sys-img2/02"
      xmlns:ns14="http://schemas.android.com/sdk/android/repo/sys-img2/01"
      xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <license id="${package.license}" type="text">${lib.concatStringsSep "---" (mkLicenses package.license)}</license>
      <localPackage path="${builtins.replaceStrings [ "/" ] [ ";" ] package.path}" obsolete="${
          if (lib.hasAttrByPath [ "optional-variables" "element-attributes" "obsolete" ] package)
          then package.optional-variables.element-attributes.obsolete else "false"
        }">
        ${mkXmlDoc "type-details" package.optional-variables.type-details}
        ${mkXmlDoc "revision" package.optional-variables.revision}
        ${lib.optionalString (lib.hasAttrByPath [ "optional-variables" "dependencies" ] package) (mkXmlDoc "dependencies" package.optional-variables.dependencies)}
        <display-name>${package.displayName}</display-name>
        <uses-license ref="${package.license}"/>
      </localPackage>
    </ns2:repository>
  '';
in
stdenv.mkDerivation ({
  pname = lib.concatMapStringsSep "-" (package: package.name) sortedPackages;
  version = lib.concatMapStringsSep "-" (package: package.revision) sortedPackages;
  src = map (package:
    if os != null && builtins.hasAttr os package.archives then package.archives.${os} else package.archives.all
  ) packages;
  buildInputs = [ unzip ] ++ buildInputs;
  preferLocalBuild = true;

  unpackPhase = ''
    buildDir=$PWD
    i=0
    for srcArchive in $src; do
      extractedZip="extractedzip-$i"
      i=$(($i+1))
      cd $buildDir
      mkdir $extractedZip
      cd "$extractedZip"
      unpackFile "$srcArchive"
    done
  '';

  installPhase = lib.concatStrings (lib.imap0 (i: package: ''
    cd $buildDir/extractedzip-${toString i}

    # Most Android Zip packages have a root folder, but some don't. We unpack
    # the zip file in a folder and we try to discover whether it has a single root
    # folder. If this is the case, we adjust the current working folder.
    if [ "$(find . -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]
    then
        cd "$(find . -mindepth 1 -maxdepth 1 -type d)"
    fi
    extractedZip="$PWD"

    packageBaseDir=$out/libexec/android-sdk/${package.path}
    mkdir -p $packageBaseDir
    cd $packageBaseDir
    cp -a $extractedZip/* .
    ${patchesInstructions.${package.name}}


    if [ ! -f $packageBaseDir/package.xml ]; then
      cat << EOF > $packageBaseDir/package.xml
    ${mkXmlPackage package}
    EOF
    fi
  '') packages);

  # We never attempt to strip. This is not required since we're doing binary
  # deployments. Moreover, some executables that have been patched with patchelf
  # may not work any longer after they have been stripped.
  dontStrip = true;
  dontPatchELF = true;
  dontAutoPatchelf = true;

  meta = {
    description = lib.concatMapStringsSep "\n" (package: package.displayName) packages;
  } // meta;
} // extraParams)
