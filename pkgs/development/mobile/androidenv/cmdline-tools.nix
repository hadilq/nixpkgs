{deployAndroidPackage, lib, package, autoPatchelfHook, makeWrapper, os, pkgs, pkgs_i686, stdenv, cmdLineToolsVersion, postInstall}:

deployAndroidPackage {
  name = "androidsdk";
  inherit package os;
  nativeBuildInputs = [ makeWrapper ]
    ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optional (os == "linux") (
    (with pkgs; [
      glibc
      zlib
      ncurses5
      freetype
      fontconfig
      fontconfig.lib
      libcxx
      libGL
      libpulseaudio
      libuuid
      stdenv.cc.cc
      expat
      nss
      nspr
      alsa-lib
    ]) ++ (with pkgs_i686; [
      glibc
      fontconfig.lib
      freetype
      zlib
    ])
  );

  patchInstructions = ''
    ${lib.optionalString (os == "linux") ''
      # Auto patch all binaries
      autoPatchelf .
    ''}

    # Strip double dots from the root path
    export ANDROID_SDK_ROOT="$out/libexec/android-sdk"

    # Wrap all scripts that require JAVA_HOME
    for i in $ANDROID_SDK_ROOT/cmdline-tools/${cmdLineToolsVersion}/bin
    do
        find $i -maxdepth 1 -type f -executable | while read program
        do
            if grep -q "JAVA_HOME" $program
            then
                wrapProgram $program  --prefix PATH : ${pkgs.jdk11}/bin \
                    --prefix ANDROID_SDK_ROOT : $ANDROID_SDK_ROOT
            fi
        done
    done

    # Wrap sdkmanager script
    wrapProgram $ANDROID_SDK_ROOT/cmdline-tools/${cmdLineToolsVersion}/bin/sdkmanager --prefix PATH : ${pkgs.jdk11}/bin \
        --add-flags "--sdk_root=$ANDROID_SDK_ROOT"

    # Patch all script shebangs
    patchShebangs $ANDROID_SDK_ROOT/cmdline-tools/${cmdLineToolsVersion}/bin

    cd $ANDROID_SDK_ROOT
    ${postInstall}
  '';

  meta.license = lib.licenses.unfree;
}
