import 'dart:async';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'metadata_collector.dart';
import 'transform_pipeline.dart';
import 'code_emitter.dart';
import 'generator_config.dart';

class BridgeGeneratorHandler {
  final _checker = const TypeChecker.fromUrl(
    'package:d4rt/src/bridge/bridge_annotations.dart#D4rtBridge',
  );

  Future<String?> generateForLibrary(
    LibraryReader library,
    BuildStep buildStep,
  ) async {
    final buffer = StringBuffer();
    final sourceCode = await buildStep.readAsString(buildStep.inputId);

    // Check if the library has any @D4rtBridge annotations
    final annotatedElements = library.annotatedWith(_checker);

    if (annotatedElements.isEmpty) {
      return null;
    }

    final config = GeneratorConfig(
      inputPaths: [], // Not used in this context
      outputPath: '', // Not used in this context
      includeAbstractClasses:
          true, // Allow generating bridges for abstract classes if annotated
    );

    final collector = MetadataCollector(config: config);
    final pipeline = TransformPipeline(config: config);
    final emitter = CodeEmitter(config: config);

    // We can collect from source directly for now to reuse existing logic
    final metadata = collector.collectFromSource(sourceCode);

    // Filter metadata to only include annotated classes/enums
    final filteredClasses = <ClassMetadata>[];
    for (final cls in metadata.classes) {
      for (final annotated in annotatedElements) {
        final element = annotated.element;
        if (element is ClassElement && element.name == cls.name) {
          filteredClasses.add(_withInheritedMembers(cls, element));
          break;
        }
      }
    }

    final filteredEnums = metadata.enums.where((e) {
      return annotatedElements.any((a) => a.element.name == e.name);
    }).toList();

    final transformed = pipeline.transform(
      CollectedMetadata(
        classes: filteredClasses,
        enums: filteredEnums,
        functions: metadata.functions,
        variables: metadata.variables,
        imports: metadata.imports,
        sourcePath: buildStep.inputId.path,
      ),
    );

    if (transformed.classes.isEmpty && transformed.enums.isEmpty) {
      return null;
    }

    final Map<String, String?> generatedClassBridges = {};
    final Map<String, String?> generatedEnumBridges = {};

    for (final cls in transformed.classes) {
      final code = emitter.emitSingleClass(cls);
      generatedClassBridges[cls.name] = cls.libraryUri;
      // Strip header/imports as source_gen handles that
      buffer.writeln(_stripBoilerplate(code));
    }

    for (final enm in transformed.enums) {
      final code = emitter.emitSingleEnum(enm);
      generatedEnumBridges[enm.name] = enm.libraryUri;
      buffer.writeln(_stripBoilerplate(code));
    }

    // Add registration function
    final inputId = buildStep.inputId;
    final sourceFileName = inputId.pathSegments.last;
    final baseName = sourceFileName.split('.').first;

    // Convert snake_case or kebab-case to PascalCase for the function name
    final pascalName = baseName
        .split(RegExp(r'[-_]'))
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .join('');

    buffer.writeln();
    buffer.writeln(
      '/// Register all $baseName bridges from this file with the interpreter.',
    );
    buffer.writeln('void register${pascalName}Bridges(D4rt interpreter) {');
    buffer.writeln("  // ignore: unused_local_variable");
    buffer.writeln("  const defaultUri = '$sourceFileName';");
    buffer.writeln();

    for (final entry in generatedClassBridges.entries) {
      final clsName = entry.key;
      final libraryUri = entry.value;
      final varName = clsName[0].toLowerCase() + clsName.substring(1);
      final uriStr = libraryUri != null ? "'$libraryUri'" : 'defaultUri';
      buffer.writeln(
        "  interpreter.registerBridgedClass(${varName}Bridge, $uriStr);",
      );
    }

    for (final entry in generatedEnumBridges.entries) {
      final enmName = entry.key;
      final libraryUri = entry.value;
      final varName = enmName[0].toLowerCase() + enmName.substring(1);
      final uriStr = libraryUri != null ? "'$libraryUri'" : 'defaultUri';
      buffer.writeln(
        "  interpreter.registerBridgedEnum(${varName}Bridge, $uriStr);",
      );
    }

    buffer.writeln('}');

    if (buffer.isEmpty) return null;
    return buffer.toString();
  }

  ClassMetadata _withInheritedMembers(ClassMetadata cls, ClassElement element) {
    final getters = [...cls.getters];
    final setters = [...cls.setters];
    final methods = [...cls.methods];
    final readNames = {
      ...cls.getters.map((member) => member.name),
      ...cls.fields.map((member) => member.name),
      ...cls.methods.map((member) => member.name),
    };
    final writeNames = {
      ...cls.setters.map((member) => member.name),
      ...cls.fields.where((field) => !field.isFinal).map((field) => field.name),
    };
    for (final member in element.interfaceMembers.values) {
      final rawName = member.name;
      if (rawName == null || !member.isPublic || member.isStatic) continue;
      final owner = member.enclosingElement;
      if (owner is ClassElement && owner.isDartCoreObject) continue;
      final name = member is SetterElement && rawName.endsWith('=')
          ? rawName.substring(0, rawName.length - 1)
          : rawName;
      if (member is GetterElement) {
        if (readNames.add(name)) {
          getters.add(
            GetterMetadata(
              name: name,
              returnType: _elementType(member.returnType),
            ),
          );
        }
      } else if (member is SetterElement) {
        if (writeNames.add(name)) {
          setters.add(
            SetterMetadata(
              name: name,
              isInherited: true,
              parameterType: _elementType(member.formalParameters.single.type),
            ),
          );
        }
      } else if (member is MethodElement) {
        if (readNames.add(name)) {
          methods.add(
            MethodMetadata(
              name: name,
              isInherited: true,
              returnType: _elementType(member.returnType),
              isOperator: member.isOperator,
              operatorSymbol: member.isOperator ? name : null,
              typeParameters: [
                for (final parameter in member.typeParameters)
                  TypeParameterMetadata(
                    name: parameter.name!,
                    bound: parameter.bound == null
                        ? null
                        : _elementType(parameter.bound!),
                  ),
              ],
              parameters: [
                for (final parameter in member.formalParameters)
                  ParameterMetadata(
                    name: parameter.name!,
                    type: _elementType(parameter.type),
                    isRequired: parameter.isRequired,
                    isNamed: parameter.isNamed,
                    defaultValue: parameter.defaultValueCode,
                  ),
              ],
            ),
          );
        }
      }
    }
    return ClassMetadata(
      name: cls.name,
      documentation: cls.documentation,
      isAbstract: cls.isAbstract,
      typeParameters: cls.typeParameters,
      superclass: cls.superclass,
      interfaces: cls.interfaces,
      mixins: cls.mixins,
      constructors: cls.constructors,
      methods: methods,
      getters: getters,
      setters: setters,
      staticMethods: cls.staticMethods,
      staticGetters: cls.staticGetters,
      staticSetters: cls.staticSetters,
      fields: cls.fields,
      staticFields: cls.staticFields,
      annotations: cls.annotations,
      location: cls.location,
    );
  }

  TypeMetadata _elementType(DartType type) {
    final text = type.getDisplayString();
    final name = text.split(RegExp(r'[<? ]')).first;
    return TypeMetadata(
      name: name,
      fullName: text,
      isNullable: text.endsWith('?'),
    );
  }

  String _stripBoilerplate(String code) {
    // Basic stripping of generated headers and imports
    final lines = code.split('\n');
    return lines
        .where((line) {
          if (line.trim().isEmpty) return true;
          if (line.startsWith('///')) {
            // Keep docs for classes but maybe not the file header
            if (line.contains('auto-generated')) return false;
            return true;
          }
          if (line.startsWith('import ')) return false;
          if (line.startsWith('library ')) return false;
          if (line.startsWith('part ')) return false;
          return true;
        })
        .join('\n');
  }
}
