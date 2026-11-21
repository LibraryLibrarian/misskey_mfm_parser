import 'package:misskey_mfm_parser/src/ast.dart';
import 'package:misskey_mfm_parser/src/parser/parser.dart';
import 'package:petitparser/petitparser.dart';
import 'package:test/test.dart';

import '../support/ast_json.dart';

void main() {
  group('mfm.js 0.28.0 fn argument assignment', () {
    final parser = MfmParser().build();

    // Expected args are literal outputs from mfm.js 0.28.0 parse(), checked
    // with Node. All inputs produce fn(x) containing text("a"); the serializer
    // also gives the leaf text node an empty children list.
    const cases = <String, Map<String, Object>>{
      r'$[x.__proto__ a]': {},
      r'$[x.__proto__=x a]': {},
      r'$[x.__proto__=null a]': {},
      r'$[x.__proto__=true a]': {},
      r'$[x.__proto__=0 a]': {},
      r'$[x.a,__proto__,b a]': {'a': true, 'b': true},
      r'$[x.a,__proto__=x,b a]': {'a': true, 'b': true},
      r'$[x.__proto__,a a]': {'a': true},
      r'$[x.__proto__=x,a a]': {'a': true},
      r'$[x.a,__proto__ a]': {'a': true},
      r'$[x.a,__proto__=x a]': {'a': true},
      r'$[x.__proto__,__proto__=x a]': {},
      r'$[x.__proto__=x,__proto__ a]': {},
      r'$[x.__proto__=x,a=1,__proto__=y,b=2 a]': {'a': '1', 'b': '2'},
      r'$[x.a=1,__proto__,a=2 a]': {'a': '2'},
      r'$[x.a=1,a a]': {'a': true},
      r'$[x.a,a=2 a]': {'a': '2'},
      r'$[x.__PROTO__ a]': {'__PROTO__': true},
      r'$[x.__PROTO__=x a]': {'__PROTO__': 'x'},
      r'$[x.__Proto__ a]': {'__Proto__': true},
      r'$[x.__Proto__=x a]': {'__Proto__': 'x'},
      r'$[x.__proto___ a]': {'__proto___': true},
      r'$[x.__proto___=x a]': {'__proto___': 'x'},
      r'$[x.__proto__,__PROTO__,__Proto__=x a]': {
        '__PROTO__': true,
        '__Proto__': 'x',
      },
      // Every other own name of Object.prototype is retained, as is prototype
      // (which is not an own name of Object.prototype).
      r'$[x.constructor a]': {'constructor': true},
      r'$[x.constructor=x a]': {'constructor': 'x'},
      r'$[x.__defineGetter__ a]': {'__defineGetter__': true},
      r'$[x.__defineGetter__=x a]': {'__defineGetter__': 'x'},
      r'$[x.__defineSetter__ a]': {'__defineSetter__': true},
      r'$[x.__defineSetter__=x a]': {'__defineSetter__': 'x'},
      r'$[x.hasOwnProperty a]': {'hasOwnProperty': true},
      r'$[x.hasOwnProperty=x a]': {'hasOwnProperty': 'x'},
      r'$[x.__lookupGetter__ a]': {'__lookupGetter__': true},
      r'$[x.__lookupGetter__=x a]': {'__lookupGetter__': 'x'},
      r'$[x.__lookupSetter__ a]': {'__lookupSetter__': true},
      r'$[x.__lookupSetter__=x a]': {'__lookupSetter__': 'x'},
      r'$[x.isPrototypeOf a]': {'isPrototypeOf': true},
      r'$[x.isPrototypeOf=x a]': {'isPrototypeOf': 'x'},
      r'$[x.propertyIsEnumerable a]': {'propertyIsEnumerable': true},
      r'$[x.propertyIsEnumerable=x a]': {'propertyIsEnumerable': 'x'},
      r'$[x.toString a]': {'toString': true},
      r'$[x.toString=x a]': {'toString': 'x'},
      r'$[x.valueOf a]': {'valueOf': true},
      r'$[x.valueOf=x a]': {'valueOf': 'x'},
      r'$[x.toLocaleString a]': {'toLocaleString': true},
      r'$[x.toLocaleString=x a]': {'toLocaleString': 'x'},
      r'$[x.prototype a]': {'prototype': true},
      r'$[x.prototype=x a]': {'prototype': 'x'},
      r'$[x.Constructor a]': {'Constructor': true},
      r'$[x.Constructor=x a]': {'Constructor': 'x'},
      r'$[x.ToString a]': {'ToString': true},
      r'$[x.ToString=x a]': {'ToString': 'x'},
      r'$[x.constructor,__proto__,toString a]': {
        'constructor': true,
        'toString': true,
      },
      r'$[x.constructor=x,constructor a]': {'constructor': true},
      r'$[x.toString,toString=x a]': {'toString': 'x'},
      r'$[x.constructor=x,__proto__,constructor=y a]': {'constructor': 'y'},
    };

    for (final entry in cases.entries) {
      test(entry.key, () {
        final result = parser.parse(entry.key);
        expect(result, isA<Success<List<MfmNode>>>());
        final success = result as Success<List<MfmNode>>;
        expect(success.position, entry.key.length);
        expect(serializeMfmAst(success.value), [
          {
            'type': 'fn',
            'props': {'name': 'x', 'args': entry.value},
            'children': [
              {
                'type': 'text',
                'props': {'text': 'a'},
                'children': <Object?>[],
              },
            ],
          },
        ]);
      });
    }
  });
}
