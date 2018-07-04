{ pkgs, haskellLib }:

with haskellLib;

self: super: {

  # Suitable LLVM version.
  llvmPackages = pkgs.llvmPackages_37;

  # https://github.com/bmillwood/applicative-quoters/issues/6
  applicative-quoters = appendPatch super.applicative-quoters (pkgs.fetchpatch {
    url = "https://patch-diff.githubusercontent.com/raw/bmillwood/applicative-quoters/pull/7.patch";
    sha256 = "026vv2k3ks73jngwifszv8l59clg88pcdr4mz0wr0gamivkfa1zy";
  });

  # Requires ghc 8.2
  ghc-proofs = dontDistribute super.ghc-proofs;

  # http://hub.darcs.net/dolio/vector-algorithms/issue/9#comment-20170112T145715
  vector-algorithms = dontCheck super.vector-algorithms;

  # https://github.com/thoughtbot/yesod-auth-oauth2/pull/77
  yesod-auth-oauth2 = doJailbreak super.yesod-auth-oauth2;

  # https://github.com/nominolo/ghc-syb/issues/20
  ghc-syb-utils = dontCheck super.ghc-syb-utils;

  # Newer versions require ghc>=8.2
  apply-refact = super.apply-refact_0_3_0_1;

  # This builds needs the latest Cabal version.
  cabal2nix = super.cabal2nix.overrideScope (self: super: { Cabal = self.Cabal_2_0_1_1; });

  # Add appropriate Cabal library to build this code.
  stack = addSetupDepend super.stack self.Cabal_2_0_1_1;

  # inline-c > 0.5.6.0 requires template-haskell >= 2.12
  inline-c = super.inline-c_0_5_6_1;
  inline-c-cpp = super.inline-c-cpp_0_1_0_0;

  # test dep hedgehog pulls in concurrent-output, which does not build
  # due to processing version mismatch
  either = dontCheck super.either;

  # test dep tasty has a version mismatch
  indents = dontCheck super.indents;

  # Newer versions require GHC 8.2.
  haddock-library = self.haddock-library_1_4_3;
  haddock-api = self.haddock-api_2_17_4;
  haddock = self.haddock_2_17_5;
}
