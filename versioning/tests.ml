open OUnit

let returns_result ?(printer=(fun _ -> "(FIXME)")) function_to_test expected_result =
  (fun args () -> assert_equal ~printer (function_to_test args) expected_result)
and raises_failure function_to_test failure_text =
  (fun args () -> assert_raises (Failure failure_text) (fun () -> function_to_test args) )


(* Test for the semantic versioning *)
open SemverNode
let get_major x = x.major
let get_minor x = x.minor
let get_patch x = x.patch

let printer x = string_of_int x

let test_parse_version_major =
  let function_to_test (v,full) = get_major (parse_version full v) in
  let returns = returns_result ~printer function_to_test in
  returns, [
    ("1.2.3",true,1);
    (" 1.2.3 ",true,1);
    (" 2.2.3-4 ",true,2);
    (" 3.2.3-pre ",true,3);
    ("v5.2.3",true,5);
    (" v8.2.3 ",true,8);
    ("\t13.2.3",true,13);
    ("=21.2.3",false,21);
    ("v=34.2.3",false,34)
  ]
    
let test_parse_version_minor =
  let function_to_test (v,full) = get_minor (parse_version full v) in
  let returns = returns_result ~printer function_to_test in
  returns, [
    ("1.1.3",true, 1);
    (" 1.1.3 ",true, 1);
    (" 1.2.3-4 ",true, 2);
    (" 1.3.3-pre ",true, 3);
    ("v1.5.3",true, 5);
    (" v1.8.3 ",true, 8);
    ("\t1.13.3",true, 13);
    ("=1.21.3",false, 21);
    ("v=1.34.3",false, 34)
  ]

let test_parse_version_patch =
  let function_to_test (v,full) = get_patch (parse_version full v) in
  let returns = returns_result ~printer function_to_test in
  returns, [
    ("1.2.1",true, 1);
    (" 1.2.1 ",true, 1);
    (" 1.2.2-4 ",true, 2);
    (" 1.2.3-pre ",true, 3);
    ("v1.2.5",true, 5);
    (" v1.2.8 ",true, 8);
    ("\t1.2.13",true, 13);
    ("=1.2.21",false, 21);
    ("v=1.2.34",false, 34)
  ]

let make_test_cases_parse (assert_function,triplets) =
  List.map ( fun (v,full,result) -> 
    v >:: assert_function result (v,full)
  ) triplets

let test_parse_and_compare_gt =
  let function_to_test (v1,v2,full) = parse_and_compare full v1 v2 in
  let returns = returns_result ~printer function_to_test in
  returns,[
    ("0.0.0","0.0.0-foo",true,1);
    ("0.0.0","0.0.0-foo",true,1);
    ("0.0.1","0.0.0",true,1);
    ("1.0.0","0.9.9",true,1);
    ("0.10.0","0.9.0",true,1);
    ("0.99.0","0.10.0",true,1);
    ("2.0.0","1.2.3",true,1);
    ("v0.0.0","0.0.0-foo",false,1);
    ("v0.0.1","0.0.0",false,1);
    ("v1.0.0","0.9.9",false,1);
    ("v0.10.0","0.9.0",false,1);
    ("v0.99.0","0.10.0",false,1);
    ("v2.0.0","1.2.3",false,1);
    ("0.0.0","v0.0.0-foo",false,1);
    ("0.0.1","v0.0.0",false,1);
    ("1.0.0","v0.9.9",false,1);
    ("0.10.0","v0.9.0",false,1);
    ("0.99.0","v0.10.0",false,1);
    ("2.0.0","v1.2.3",false,1);
    ("1.2.3","1.2.3-asdf",true,1);
    ("1.2.3","1.2.3-4",true,1);
    ("1.2.3","1.2.3-4-foo",true,1);
    ("1.2.3-5-foo","1.2.3-5",true,1);
    ("1.2.3-5","1.2.3-4",true,1);
    ("1.2.3-5-foo","1.2.3-5-Foo",true,1);
    ("3.0.0","2.7.2+asdf",true,1);
    ("1.2.3-a.10","1.2.3-a.5",true,1);
    ("1.2.3-a.b","1.2.3-a.5",true,1);
    ("1.2.3-a.b","1.2.3-a",true,1);
    ("1.2.3-a.b.c.10.d.5","1.2.3-a.b.c.5.d.100",true,1);
    ("1.2.3-r2","1.2.3-r100",true,1);
    ("1.2.3-r100","1.2.3-R2",true,1)
  ]

let test_parse_and_compare_eq =
  let function_to_test (v1,v2,full) = parse_and_compare full v1 v2 in
  let returns = returns_result ~printer function_to_test in
  returns,[
    ("1.2.3","v1.2.3",true,0);
    ("1.2.3","=1.2.3",false,0);
    ("1.2.3","v 1.2.3",false,0);
    ("1.2.3","= 1.2.3",false,0);
    ("1.2.3"," v1.2.3",false,0);
    ("1.2.3"," =1.2.3",false,0);
    ("1.2.3"," v 1.2.3",false,0);
    ("1.2.3"," = 1.2.3",false,0);
    ("1.2.3-0","v1.2.3-0",false,0);
    ("1.2.3-0","=1.2.3-0",false,0);
    ("1.2.3-0","v 1.2.3-0",false,0);
    ("1.2.3-0","= 1.2.3-0",false,0);
    ("1.2.3-0"," v1.2.3-0",false,0);
    ("1.2.3-0"," =1.2.3-0",false,0);
    ("1.2.3-0"," v 1.2.3-0",false,0);
    ("1.2.3-0"," = 1.2.3-0",false,0);
    ("1.2.3-1","v1.2.3-1",false,0);
    ("1.2.3-1","=1.2.3-1",false,0);
    ("1.2.3-1","v 1.2.3-1",false,0);
    ("1.2.3-1","= 1.2.3-1",false,0);
    ("1.2.3-1"," v1.2.3-1",false,0);
    ("1.2.3-1"," =1.2.3-1",false,0);
    ("1.2.3-1"," v 1.2.3-1",false,0);
    ("1.2.3-1"," = 1.2.3-1",false,0);
    ("1.2.3-beta","v1.2.3-beta",false,0);
    ("1.2.3-beta","=1.2.3-beta",false,0);
    ("1.2.3-beta","v 1.2.3-beta",false,0);
    ("1.2.3-beta","= 1.2.3-beta",false,0);
    ("1.2.3-beta"," v1.2.3-beta",false,0);
    ("1.2.3-beta"," =1.2.3-beta",false,0);
    ("1.2.3-beta"," v 1.2.3-beta",false,0);
    ("1.2.3-beta"," = 1.2.3-beta",false,0);
    ("1.2.3-beta+build"," = 1.2.3-beta+otherbuild",false,0);
    ("1.2.3+build"," = 1.2.3+otherbuild",false,0);
    ("1.2.3-beta+build","1.2.3-beta+otherbuild",true,0);
    ("1.2.3+build","1.2.3+otherbuild",true,0);
    ("  v1.2.3+build","1.2.3+otherbuild",true,0)
  ]


let make_test_cases_compare (assert_function,triplets) =
  List.map ( fun (v1,v2,full,result) -> 
    (Printf.sprintf "%s - %s" v1 v2) >:: assert_function result (v1,v2,full)
  ) triplets




let suite = 
  "suite" >::: [ 
    "test_parse_version_major" >::: make_test_cases_parse test_parse_version_major;
    "test_parse_version_minor" >::: make_test_cases_parse test_parse_version_minor;
    "test_parse_version_patch" >::: make_test_cases_parse test_parse_version_patch;
    "test_parse_and_compare_gt" >::: make_test_cases_compare test_parse_and_compare_gt;
    "test_parse_and_compare_eq" >::: make_test_cases_compare test_parse_and_compare_eq;
  ]

let main () = OUnit.run_test_tt_main suite ;;
main ()
